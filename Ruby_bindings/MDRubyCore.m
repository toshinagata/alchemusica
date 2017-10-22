/*
 *  MDRubyCore.m
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 08/03/19.
 *  Copyright 2008-2017 Toshi Nagata. All rights reserved.
 *
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>
#include "MDRuby.h"

#import "MyDocument.h"
#import "MyMIDISequence.h"
#import "MDObjects.h"

#include <sys/time.h> /*  for gettimeofday()  */
#include <time.h>     /*  for clock()  */
#include <signal.h>   /*  for sigaction()  */

#include <pthread.h>  /*  for pthread implementation of interval timer  */

//  Global variables
int gRubyRunLevel = 0;
int gRubyIsCheckingInterrupt = 0;

VALUE gRubyBacktrace;
VALUE gRubyErrorHistory;

#pragma mark ====== Utility function ======

/*
 *  Utility function
 *  Get ary[i] by calling "[]" method
 */
VALUE
Ruby_ObjectAtIndex(VALUE ary, int idx)
{
	static ID index_method = 0;
	if (TYPE(ary) == T_ARRAY) {
		int len = (int)RARRAY_LEN(ary);
		if (idx >= 0 && idx < len)
			return (RARRAY_PTR(ary))[idx];
		else return Qnil;
	}
	if (index_method == 0)
		index_method = rb_intern("[]");
	return rb_funcall(ary, index_method, 1, INT2NUM(idx));
}

char *
Ruby_FileStringValuePtr(VALUE *valp)
{
#if WINDOWS
	char *p = strdup(StringValuePtr(*valp));
	translate_char(p, '/', '¥¥');
	*valp = rb_str_new2(p);
	free(p);
	return StringValuePtr(*valp);
#else
	return StringValuePtr(*valp);
#endif
}

VALUE
Ruby_NewFileStringValue(const char *fstr)
{
#if WINDOWS
	VALUE retval;
	char *p = strdup(fstr);
	translate_char(p, '¥¥', '/');
	retval = rb_str_new2(p);
	free(p);
	return retval;
#else
	return rb_str_new2(fstr);
#endif
}

char *
Ruby_EncodedStringValuePtr(VALUE *valp)
{
	rb_string_value(valp);
	*valp = rb_str_encode(*valp, rb_enc_from_encoding(rb_default_external_encoding()), 0, Qnil);
	return RSTRING_PTR(*valp);
}

VALUE
Ruby_NewEncodedStringValue(const char *str, int len)
{
	if (len <= 0)
		len = (int)strlen(str);
	return rb_enc_str_new(str, len, rb_default_external_encoding());
}

VALUE
Ruby_ObjToStringObj(VALUE val)
{
	switch (TYPE(val)) {
		case T_STRING:
			return val;
		case T_SYMBOL:
			return rb_str_new2(rb_id2name(SYM2ID(val)));
		default:
			return rb_str_to_str(val);
	}
}

void
Ruby_getVersionStrings(const char **version, const char **copyright)
{
	static char *s_ruby_copyright;
	*version = ruby_version;
	if (s_ruby_copyright == NULL)
		asprintf(&s_ruby_copyright, "Copyright (C) %d-%d %s", RUBY_BIRTH_YEAR, 2013, RUBY_AUTHOR);
	*copyright = s_ruby_copyright;
}


#pragma mark ====== Message output ======

/*
 *  call-seq:
 *     MessageOutput.write(str)
 *
 *  Put the message in the main text view.
 */
static VALUE
s_MessageOutput_Write(VALUE self, VALUE str)
{
	int n = MyAppCallback_showScriptMessage("%s", StringValuePtr(str));
	return INT2NUM(n);
}

/*
 *  call-seq:
 *     message_box(str, title, button = nil, icon = :info)
 *
 *  Show a message box.
 *  Buttons: nil (ok and cancel), :ok (ok only), :cancel (cancel only)
 *  Icon: :info, :warning, :error
 */
static VALUE
s_Kernel_MessageBox(int argc, VALUE *argv, VALUE self)
{
	char *str, *title, *s;
	int buttons, icon;
	VALUE sval, tval, bval, ival;
	rb_scan_args(argc, argv, "22", &sval, &tval, &bval, &ival);
	str = StringValuePtr(sval);
	title = StringValuePtr(tval);
	if (bval != Qnil) {
		bval = Ruby_ObjToStringObj(bval);
		s = RSTRING_PTR(bval);
		if (strncmp(s, "ok", 2) == 0)
			buttons = 1;
		else if (strncmp(s, "cancel", 6) == 0)
			buttons = 2;
		else
			rb_raise(rb_eStandardError, "the button specification should be either nil, :ok or :cancel");
	} else buttons = 3;
	if (ival != Qnil) {
		ival = Ruby_ObjToStringObj(ival);
		s = RSTRING_PTR(ival);
		if (strncmp(s, "info", 4) == 0)
			icon = 1;
		else if (strncmp(s, "warn", 4) == 0)
			icon = 2;
		else if (strncmp(s, "err", 3) == 0)
			icon = 3;
		else
			rb_raise(rb_eStandardError, "the icon specification should be either :info, :warning or :error");
	} else icon = 1;
	MyAppCallback_messageBox(str, title, buttons, icon);
	return Qnil;
}

#pragma mark ====== Track key events ======

/*  User interrupt handling
 *  User interrupt (command-period on Mac OS) is handled by periodic polling of
 *  key events. This polling should only be enabled during "normal" execution
 *  of scripts and must be disabled when the rest of the application (or Ruby
 *  script itself) is handling GUI. This is ensured by appropriate calls to
 *  enable_interrupt and disable_interrupt.  */

static VALUE s_interrupt_flag = Qfalse;

static VALUE
s_ShowProgressPanel(int argc, VALUE *argv, VALUE self)
{
	volatile VALUE message;
	const char *p;
	if (Ruby_GetInterruptFlag() == Qtrue) {
		rb_scan_args(argc, argv, "01", &message);
		if (message != Qnil)
			p = StringValuePtr(message);
		else
			p = NULL;
		MyAppCallback_showProgressPanel(p);
	}
	return Qnil;
}

static VALUE
s_HideProgressPanel(VALUE self)
{
	MyAppCallback_hideProgressPanel();
	return Qnil;
}

static VALUE
s_SetProgressValue(VALUE self, VALUE val)
{
	double dval = NUM2DBL(rb_Float(val));
	MyAppCallback_setProgressValue(dval);
	return Qnil;
}

static VALUE
s_SetProgressMessage(VALUE self, VALUE msg)
{
	const char *p;
	if (msg == Qnil)
		p = NULL;
	else p = StringValuePtr(msg);
	MyAppCallback_setProgressMessage(p);
	return Qnil;
}

static VALUE
s_SetInterruptFlag(VALUE self, VALUE val)
{
	VALUE oldval;
	if (val != Qundef) {
		if (val == Qfalse || val == Qnil)
			val = Qfalse;
		else val = Qtrue;
	}
	oldval = s_interrupt_flag;
	if (val != Qundef) {
		s_interrupt_flag = val;
		if (val == Qfalse) {
			s_HideProgressPanel(self);
		}
	}
	return oldval;
}

static VALUE
s_GetInterruptFlag(VALUE self)
{
	return s_SetInterruptFlag(self, Qundef);
}

/*
static VALUE
s_Ruby_CallMethod(VALUE val)
{
	void **ptr = (void **)val;
	VALUE receiver = (VALUE)ptr[0];
	ID method_id = (ID)ptr[1];
	VALUE args = (VALUE)ptr[2];
	VALUE retval;
	if (method_id == 0) {
		//  args should be a string, which is evaluated
		if (receiver == Qnil) {
			retval = rb_eval_string(StringValuePtr(args));
		} else {
			retval = rb_obj_instance_eval(1, &args, receiver);
		}
	} else {
		//  args should be an array of arguments
		retval = rb_apply(receiver, method_id, args);
	}
	return retval;
}
*/
/*
VALUE
Ruby_CallMethodWithInterrupt(VALUE receiver, ID method_id, VALUE args, int *status)
{
	VALUE retval, save_interrupt_flag;
	void *ptr[3];
	save_interrupt_flag = s_SetInterruptFlag(Qnil, Qtrue);
	ptr[0] = (void *)receiver;
	ptr[1] = (void *)method_id;
	ptr[2] = (void *)args;
	retval = rb_protect(s_Ruby_CallMethod, (VALUE)ptr, status);
	s_SetInterruptFlag(Qnil, save_interrupt_flag);
	MyAppCallback_hideProgressPanel();  //  In case when the progress panel is still onscreen
	return retval;
}
*/

VALUE
Ruby_SetInterruptFlag(VALUE val)
{
	return s_SetInterruptFlag(Qnil, val);
}

VALUE
Ruby_GetInterruptFlag(void)
{
	return s_SetInterruptFlag(Qnil, Qundef);
}

/*
 *  call-seq:
 *     check_interrupt -> integer
 *
 *  Returns 1 if interrupted, 0 if not, -1 if interrupt is disabled.
 */
static VALUE
s_Kernel_CheckInterrupt(VALUE self)
{
	if (Ruby_GetInterruptFlag() == Qfalse)
		return INT2NUM(-1);
	else if (MyAppCallback_checkInterrupt())
		return INT2NUM(1);
	else return INT2NUM(0);
}

#define USE_SIGALRM 0

static volatile uint32_t sITimerCount = 0;

#if !USE_SIGALRM
static pthread_t sTimerThread;

/*  -1: uninitiated; 0: active, 1: inactive, -2: request to terminate  */
static volatile signed char sTimerFlag = -1;

static void *
s_TimerThreadEntry(void *param)
{
	while (1) {
		my_usleep(50000);
		if (sTimerFlag == 0)
			sITimerCount++;
		else if (sTimerFlag == -2)
			break;
	}
	return NULL;	
}

#else
static void
s_SignalAction(int n)
{
	sITimerCount++;
}
#endif
static void
s_SetIntervalTimer(int n)
{
#if !USE_SIGALRM
	if (n == 0) {
		if (sTimerFlag == -1) {
			int status = pthread_create(&sTimerThread, NULL, s_TimerThreadEntry, NULL);
			if (status != 0) {
				fprintf(stderr, "pthread_create failed while setting Ruby interval timer: status = %d¥n", status);
			}
		}
		sTimerFlag = 0;  /*  Active  */
	} else if (sTimerFlag != -1)
		sTimerFlag = 1;  /*  Inactive  */
#else
	static struct itimerval sOldValue;
	static struct sigaction sOldAction;
	struct itimerval val;
	struct sigaction act;
	if (n == 0) {
		sITimerCount = 0;
		act.sa_handler = s_SignalAction;
		act.sa_mask = 0;
		act.sa_flags = 0;
		sigaction(SIGALRM, &act, &sOldAction);
		val.it_value.tv_sec = 0;
		val.it_value.tv_usec = 50000;  /*  50 msec  */
		val.it_interval.tv_sec = 0;
		val.it_interval.tv_usec = 50000;
		setitimer(ITIMER_REAL, &val, &sOldValue);
	} else {
		setitimer(ITIMER_REAL, &sOldValue, &val);
		sigaction(SIGALRM, &sOldAction, &act);
	}
#endif
}
	
static void
s_Event_Callback(rb_event_flag_t evflag, VALUE data, VALUE self, ID mid, VALUE klass)
{
	if (s_interrupt_flag != Qfalse) {
		static uint32_t sLastTime = 0;
		uint32_t currentTime;
		int flag;
		currentTime = sITimerCount;
		if (currentTime != sLastTime) {
			sLastTime = currentTime;
			gRubyIsCheckingInterrupt = 1;
			flag = MyAppCallback_checkInterrupt();
			gRubyIsCheckingInterrupt = 0;
			if (flag) {
				s_SetInterruptFlag(Qnil, Qfalse);
				rb_interrupt();
			}
		}
	}
}

#pragma mark ====== Menu handling ======

/*  Array of menu validators (to avoid garbage collection)  */
static VALUE sValidatorList = Qnil;

/*
 *  call-seq:
 *     register_menu(title, method, validator = nil)
 *
 *  Register the method (specified as a symbol) in the script menu.
 *  The method must be either an instance method of Sequence with no argument,
 *  or a class method of Sequence with one argument (the current Sequence).
 *  The menu associated with the class method can be invoked even when no document
 *  is open (the argument is set to Qnil in this case). On the other hand, the
 *  menu associated with the instance method can only be invoked when at least one 
 *  document is active.
 *  Validator controls how the menu item is activated. If it is nil, then
 *  the menu is either 'always activated' (when method is a class method) or 'activated
 *  if there is an open document' (when method is an instance method). If it is a numeric
 *  1 (one), then the menu is activated when there is an open document and at least one
 *  event is selected (in any track). Otherwise, the validator should be a callable
 *  object with one MRSequence argument, and if it returns 'true' (in Ruby sense)
 *  then the menu is activated.
 */
static VALUE
s_Kernel_RegisterMenu(int argc, VALUE *argv, VALUE self)
{
	VALUE title, method, validator;
	rb_scan_args(argc, argv, "21", &title, &method, &validator);
	if (TYPE(method) == T_SYMBOL) {
		method = rb_funcall(method, rb_intern("to_s"), 0);
	}
	if (validator != Qnil && !FIXNUM_P(validator)) {
		if (sValidatorList == Qnil) {
			sValidatorList = rb_ary_new();
			rb_define_variable("_validator_list", &sValidatorList);
		}
		rb_ary_push(sValidatorList, validator);
	}
	MyAppCallback_registerScriptMenu(StringValuePtr(method), StringValuePtr(title), (int32_t)validator);
	return self;
}

static VALUE
s_MDRuby_methodType_sub(VALUE data)
{
	const char **p = (const char **)data;
	VALUE klass = rb_const_get(rb_cObject, rb_intern(p[0]));
	ID mid = rb_intern(p[1]);
	int ival;
	if (rb_funcall(klass, rb_intern("method_defined?"), 1, ID2SYM(mid)) != Qfalse)
		ival = 1;
	else if (rb_respond_to(klass, mid))
		ival = 2;
	else ival = 0;
	return INT2FIX(ival);
}
	
/*  Returns 1 if the class defines the instance method with the given name, 2 if the class
    has the singleton method (class method) with the given name, 0 otherwise.  */
int
Ruby_methodType(const char *className, const char *methodName)
{
	int status;
	VALUE retval;
	const char *p[2];
	p[0] = className;
	p[1] = methodName;
	retval = rb_protect(s_MDRuby_methodType_sub, (VALUE)p, &status);
	if (status == 0)
		return FIX2INT(retval);
	else return 0;
}

static VALUE
s_Ruby_callValidatorForDocument(VALUE data)
{
	VALUE *v = (VALUE *)data;
	MyDocument *doc = (MyDocument *)v[1];
	if (v[0] == Qnil) {
		/*  No validator: default behavior (it is already handled by MyDocument)  */
		return Qtrue;
	} else if (v[0] == INT2FIX(0)) {
		/*  Valid if document is open  */
		return (doc != NULL ? Qtrue : Qfalse);
	} else if (v[0] == INT2FIX(1)) {
		/*  Valid if document is open and some events are selected  */
		int32_t n, c;
		if (doc == NULL)
			return Qfalse;
		c = [[doc myMIDISequence] trackCount];
		for (n = 0; n < c; n++) {
			IntGroup *pset = [[doc selectionOfTrack:n] pointSet];
			if (IntGroupGetCount(pset) > 0)
				break;
		}
		return (n < c ? Qtrue : Qfalse);
	}
	return rb_funcall(v[0], rb_intern("call"), 1, (doc == NULL ? Qnil : MRSequenceFromMyDocument(doc)));
}

int
Ruby_callValidatorForDocument(int32_t validator, void *doc)
{
	VALUE v[3];
	VALUE retval;
	int status;
	v[0] = (VALUE)validator;
	v[1] = (VALUE)doc;
	retval = rb_protect(s_Ruby_callValidatorForDocument, (VALUE)&v, &status);
	if (status == 0 && RTEST(retval))
		return 1;
	else return 0;
}

/*
 *  call-seq:
 *     execute_script_file(fname)
 *
 *  Execute the script in the given file. If a molecule is active, then
 *  the script is evaluated as Molecule.current.instance_eval(script).
 *  Before entering the script, the current directory is set to the parent
 *  directory of the script.
 */
static VALUE
s_Kernel_ExecuteScript(VALUE self, VALUE fname)
{
	int status;
	VALUE retval = (VALUE)MyAppCallback_executeScriptFromFile(StringValuePtr(fname), &status);
	if (status != 0)
		rb_jump_tag(status);
	return retval;
}

#pragma mark ====== User defaults ======

/*
 *  call-seq:
 *     Kernel.get_global_settings(key)
 *
 *  Get a setting data for key from the application preferences.
 */
static VALUE
s_Kernel_GetGlobalSettings(VALUE self, VALUE key)
{
	const char *p = MyAppCallback_getGlobalSettings(StringValuePtr(key));
	if (p != NULL) {
		return rb_str_new2(p);
	} else return Qnil;
}

/*
 *  call-seq:
 *     Kernel.set_global_settings(key, value)
 *
 *  Set a setting data for key to the application preferences.
 */
static VALUE
s_Kernel_SetGlobalSettings(VALUE self, VALUE key, VALUE value)
{
	key = rb_obj_as_string(key);
	value = rb_obj_as_string(value);
	MyAppCallback_setGlobalSettings(StringValuePtr(key), StringValuePtr(value));
	return value;
}

/*
 *  call-seq:
 *     Kernel.sanity_check(boolean = current value)
 *
 *  Set whether track data check is done after every editing operation
 */
static VALUE
s_Kernel_SanityCheck(int argc, VALUE *argv, VALUE self)
{
	extern int gMyDocumentSanityCheck;
	VALUE fval = Qnil;
	if (argc > 0)
		fval = argv[0];
	if (fval != Qnil) {
		gMyDocumentSanityCheck = (RTEST(fval) ? 1 : 0);
	}
	return gMyDocumentSanityCheck ? Qtrue :Qfalse;
}


#pragma mark ====== Utility functions (protected funcall) ======

struct Ruby_funcall2_record {
	VALUE recv;
	ID mid;
	int argc;
	VALUE *argv;
};

static VALUE
s_Ruby_funcall2_sub(VALUE data)
{
	struct Ruby_funcall2_record *rp = (struct Ruby_funcall2_record *)data;
	return rb_funcall2(rp->recv, rp->mid, rp->argc, rp->argv);
}

VALUE
Ruby_funcall2_protect(VALUE recv, ID mid, int argc, VALUE *argv, int *status)
{
	struct Ruby_funcall2_record rec;
	rec.recv = recv;
	rec.mid = mid;
	rec.argc = argc;
	rec.argv = argv;
	return rb_protect(s_Ruby_funcall2_sub, (VALUE)&rec, status);
}

#pragma mark ====== Initialize class ======

void
MRCoreInitClass(void)
{	
	/*  module Kernel  */
	rb_define_method(rb_mKernel, "check_interrupt", s_Kernel_CheckInterrupt, 0);
	rb_define_method(rb_mKernel, "get_interrupt_flag", s_GetInterruptFlag, 0);
	rb_define_method(rb_mKernel, "set_interrupt_flag", s_SetInterruptFlag, 1);
	rb_define_method(rb_mKernel, "show_progress_panel", s_ShowProgressPanel, -1);
	rb_define_method(rb_mKernel, "hide_progress_panel", s_HideProgressPanel, 0);
	rb_define_method(rb_mKernel, "set_progress_value", s_SetProgressValue, 1);
	rb_define_method(rb_mKernel, "set_progress_message", s_SetProgressMessage, 1);
	rb_define_method(rb_mKernel, "register_menu", s_Kernel_RegisterMenu, -1);
	rb_define_method(rb_mKernel, "get_global_settings", s_Kernel_GetGlobalSettings, 1);
	rb_define_method(rb_mKernel, "set_global_settings", s_Kernel_SetGlobalSettings, 2);
	rb_define_method(rb_mKernel, "execute_script", s_Kernel_ExecuteScript, 1);
	rb_define_method(rb_mKernel, "sanity_check", s_Kernel_SanityCheck, -1);
	rb_define_method(rb_mKernel, "message_box", s_Kernel_MessageBox, -1);
}

#pragma mark ====== External functions ======

typedef struct RubyArgsRecord {
	void *doc;          /*  A pointer to document  */
	const char *script; /*  A method name or a script  */
	int type;           /*  0: script, 1: ordinary method, 2: singleton method  */
	const char *argfmt; /*  Argument format string  */
	const char *fname;  /*  Not used yet  */
	va_list ap;			/*  Argument list  */
} RubyArgsRecord;

static VALUE s_ruby_top_self = Qfalse;
static VALUE s_ruby_get_binding_for_document = Qfalse;
static VALUE s_ruby_export_local_variables = Qfalse;

static VALUE
s_evalRubyScriptOnDocumentSub(VALUE val)
{
	RubyArgsRecord *arec = (RubyArgsRecord *)val;
	VALUE sval, fnval, lnval, retval;
	VALUE binding;
	
	/*  Clear the error information (store in the history array if necessary)  */
	sval = rb_errinfo();
	if (sval != Qnil) {
		rb_eval_string("$error_history.push([$!.to_s, $!.backtrace])");
		rb_set_errinfo(Qnil);
	}
	
	if (s_ruby_top_self == Qfalse) {
		s_ruby_top_self = rb_eval_string("eval(\"self\",TOPLEVEL_BINDING)");
	}
	if (s_ruby_get_binding_for_document == Qfalse) {
		const char *s1 =
		"lambda { |_doc_, _bind_| \n"
		"  _proc_ = eval(\"lambda { |__doc__| __doc__.instance_eval { binding } } \", _bind_) \n"
		"  _proc_.call(_doc_) } ";
		s_ruby_get_binding_for_document = rb_eval_string(s1);
		rb_define_variable("_get_binding_for_document", &s_ruby_get_binding_for_document);
	}
	if (s_ruby_export_local_variables == Qfalse) {
		const char *s2 =
		"lambda { |_bind_| \n"
		"   # find local variables newly defined in _bind_ \n"
		" _a_ = _bind_.eval(\"local_variables\") - TOPLEVEL_BINDING.eval(\"local_variables\"); \n"
		" _a_.each { |_vsym_| \n"
		"   _vname_ = _vsym_.to_s \n"
		"   _vval_ = _bind_.eval(_vname_) \n"
		"   #  Define local variable \n"
		"   TOPLEVEL_BINDING.eval(_vname_ + \" = nil\") \n"
		"   #  Then set value  \n"
		"   TOPLEVEL_BINDING.eval(\"lambda { |_m_| \" + _vname_ + \" = _m_ }\").call(_vval_) \n"
		" } \n"
		"}";
		s_ruby_export_local_variables = rb_eval_string(s2);
		rb_define_variable("_export_local_variables", &s_ruby_export_local_variables);
	}
	if (arec->fname == NULL) {
		char *scr;
		/*  String literal: we need to specify string encoding  */
		asprintf(&scr, "#coding:utf-8\n%s", arec->script);
		sval = rb_str_new2(scr);
		free(scr);
		fnval = rb_str_new2("(eval)");
		lnval = INT2FIX(0);
	} else {
		sval = rb_str_new2(arec->script);
		fnval = Ruby_NewFileStringValue(arec->fname);
		lnval = INT2FIX(1);
	}
	binding = rb_const_get(rb_cObject, rb_intern("TOPLEVEL_BINDING"));
	if (arec->doc != NULL) {
		VALUE mval = MRSequenceFromMyDocument(arec->doc);
		binding = rb_funcall(s_ruby_get_binding_for_document, rb_intern("call"), 2, mval, binding);
	}
	retval = rb_funcall(binding, rb_intern("eval"), 3, sval, fnval, lnval);
	if (arec->doc != NULL) {
		rb_funcall(s_ruby_export_local_variables, rb_intern("call"), 1, binding);
	}
	return retval;
}

RubyValue
Ruby_evalRubyScriptOnDocument(const char *script, void *doc, int *status)
{
	RubyValue retval;
	RubyArgsRecord rec;
	VALUE save_interrupt_flag;
	/*	char *save_ruby_sourcefile;
	 int save_ruby_sourceline; */
	if (gRubyIsCheckingInterrupt) {
		//  TODO: Show alert
		// MolActionAlertRubyIsRunning();
		*status = -1;
		return (RubyValue)Qnil;
	}
	gRubyRunLevel++;
	memset(&rec, 0, sizeof(rec));
	rec.doc = doc;
	rec.script = script;
	rec.type = 0;
	//  TODO: support fname?
	// args[2] = (void *)fname;
	save_interrupt_flag = s_SetInterruptFlag(Qnil, Qtrue);
	retval = (RubyValue)rb_protect(s_evalRubyScriptOnDocumentSub, (VALUE)&rec, status);
	if (*status != 0) {
		/*  Is this 'exit' exception?  */
		VALUE last_exception = rb_gv_get("$!");
		if (rb_obj_is_kind_of(last_exception, rb_eSystemExit)) {
			/*  Capture exit and return the status value  */
			retval = (RubyValue)rb_funcall(last_exception, rb_intern("status"), 0);
			*status = 0;
			rb_set_errinfo(Qnil);
		}
	}
	s_SetInterruptFlag(Qnil, save_interrupt_flag);
	gRubyRunLevel--;
	return retval;	
}

static VALUE
s_executeRubyOnDocument(VALUE vinfo)
{
	VALUE retval, args, aval, mval;
	int i, n;
	ID mid;
	char retfmt = 0;
	void *retp1, *retp2, *retp3;
	RubyArgsRecord *rp = (RubyArgsRecord *)vinfo;
	VALUE save_interrupt_flag;
	
	if (rp->type == 0) {
		/*  Evaluate as string (no other arguments)  */
		save_interrupt_flag = s_SetInterruptFlag(Qnil, Qtrue);
		if (rp->doc == NULL)
			retval = rb_eval_string(rp->script);
		else {
			aval = rb_str_new2(rp->script);
			mval = MRSequenceFromMyDocument(rp->doc);
			retval = rb_obj_instance_eval(1, &aval, mval);
		}
		s_SetInterruptFlag(Qnil, save_interrupt_flag);
		return retval;
	}

	mval = MRSequenceFromMyDocument(rp->doc);
	mid = rb_intern(rp->script);
	args = rb_ary_new();
	save_interrupt_flag = s_SetInterruptFlag(Qnil, Qtrue);

	/*  Analyse the argfmt  */
	if (rp->argfmt != NULL && rp->argfmt[0] != 0) {
		const char *p = rp->argfmt;
		int ival;
	/*	va_list ap = rp->ap; *//*  This assignment does not work on 64-bit build  */
		while (*p != 0) {
			switch (*p) {
				case 'b': 
					ival = va_arg(rp->ap, int);
					aval = (ival ? Qtrue : Qfalse);
					break;
				case 'i':
					aval = INT2NUM(va_arg(rp->ap, int)); break;
				case 'l':
					aval = INT2NUM(va_arg(rp->ap, int32_t)); break;
				case 'q':
					aval = LL2NUM(va_arg(rp->ap, int64_t)); break;
				case 'd':
					aval = rb_float_new(va_arg(rp->ap, double)); break;
				case 's':
					aval = rb_str_new2(va_arg(rp->ap, const char *)); break;
				case 'a':  /*  ASCII characters (can contain NUL)  */
					n = va_arg(rp->ap, int);
					aval = rb_str_new(va_arg(rp->ap, const char *), n);
					break;
				case 'B': case 'I': case 'L': case 'Q': case 'D': case 'S': case 'A': {
					VALUE aaval;
					void *pp;
					n = va_arg(rp->ap, int);
					pp = va_arg(rp->ap, void *);
					aval = rb_ary_new2(n);
					for (i = 0; i < n; i++) {
						switch (*p) {
							case 'B':
								ival = ((int *)pp)[i];
								aaval = (ival ? Qtrue : Qfalse);
								break;
							case 'I':
								aaval = INT2NUM(((int *)pp)[i]); break;
							case 'L':
								aaval = INT2NUM(((int32_t *)pp)[i]); break;
							case 'Q':
								aaval = LL2NUM(((int64_t *)pp)[i]); break;
							case 'D':
								aaval = rb_float_new(((double *)pp)[i]); break;
							case 'S':
								aaval = rb_str_new2(((const char **)pp)[i]); break;
						}
						rb_ary_push(aval, aaval);
					}
					break;
				}
				case ';':
					retfmt = *++p;
					retp1 = va_arg(rp->ap, void *);
					if (retfmt == 'a' || (retfmt >= 'A' && retfmt <= 'Z'))
						retp2 = va_arg(rp->ap, void *);
					goto out_of_loop;
			} /* end switch */
			rb_ary_push(args, aval);
			p++;
		} /* end while */
	} /* end if */
	
out_of_loop:
	if (rp->type == 2) {
		rb_ary_unshift(args, mval);
		retval = rb_apply(rb_cMRSequence, mid, args);
	} else {
		retval = rb_apply(mval, mid, args);
	}
	switch (retfmt) {
		case 'b':
			*((int *)retp1) = RTEST(retval); break;
		case 'i':
			*((int *)retp1) = NUM2INT(rb_Integer(retval)); break;
		case 'l':
			*((int32_t *)retp1) = NUM2INT(rb_Integer(retval)); break;
		case 'q':
			*((int64_t *)retp1) = NUM2LL(rb_Integer(retval)); break;
		case 'd':
			*((double *)retp1) = NUM2DBL(rb_Float(retval)); break;
		case 's':
			*((char **)retp1) = strdup(StringValuePtr(retval)); break;
		case 'a':
			retval = rb_str_to_str(retval);
			n = (int)RSTRING_LEN(retval);
			*((int *)retp1) = n;
			retp3 = malloc(n + 1);
			memmove(retp3, RSTRING_PTR(retval), n);
			((char *)retp3)[n] = 0;
			*((void **)retp2) = retp3;
			break;
		case 'B': case 'I': case 'L': case 'Q': case 'D': case 'S':
			switch (retfmt) {
				case 'B': case 'I': i = sizeof(int); break;
				case 'L': i = sizeof(int32_t); break;
				case 'Q': i = sizeof(int64_t); break;
				case 'D': i = sizeof(double); break;
				case 'S': i = sizeof(char *); break;
			}
			if (retval == Qnil)
				n = 0;
			else {
				retval = rb_ary_to_ary(retval);
				n = (int)RARRAY_LEN(retval);
			}
			*((int *)retp1) = n;
			if (n == 0)
				retp3 = NULL;
			else {
				retp3 = calloc(n, i);
				for (i = 0; i < n; i++) {
					aval = RARRAY_PTR(retval)[i];
					switch (retfmt) {
						case 'B': ((int *)retp3)[i] = RTEST(aval); break;
						case 'I': ((int *)retp3)[i] = NUM2INT(rb_Integer(aval)); break;
						case 'L': ((int32_t *)retp3)[i] = NUM2INT(rb_Integer(aval)); break;
						case 'Q': ((int64_t *)retp3)[i] = NUM2LL(rb_Integer(aval)); break;
						case 'D': ((double *)retp3)[i] = NUM2DBL(rb_Float(aval)); break;
						case 'S': ((char **)retp3)[i] = strdup(StringValuePtr(aval)); break;
					}
				}
			}
			*((void **)retp2) = retp3;
			break;
	}
	s_SetInterruptFlag(Qnil, save_interrupt_flag);
	return retval;
}

/*  argfmt: characters representing the arguments
    b: boolean (int), i: integer, l: int32_t integer, q: int64_t integer,
    d: double, s: string (const char *),
    B, I, L, Q, D, S: array of the above type (two arguments: number of values followed by a pointer)
    ;X (X is one of the above types): return value; if the type is a simple type (represented by
    a lowercase character), one pointer (TYPE *) is required. If the type is an array type, 
    two pointers (int * and TYPE **) are required. On returning a string or an array, the 
    required storage are allocated by malloc() (i.e. the caller is responsible for free'ing them).
    If the return value is an array of strings, each string should be free'd.  */
int
Ruby_callMethodOfDocument(const char *name, void *document, int isSingleton, const char *argfmt, ...)
{
	RubyArgsRecord rec;
	int status;
	rec.doc = document;
	rec.script = name;
	rec.type = isSingleton + 1;
	rec.argfmt = argfmt;
	va_start(rec.ap, argfmt);
	rb_protect(s_executeRubyOnDocument, (VALUE)&rec, &status);
	return status;
}

int
Ruby_showValue(RubyValue value, char **outValueString)
{
	VALUE val = (VALUE)value;
	if (gRubyIsCheckingInterrupt) {
		//  TODO: show error message
		return 0;
	}
	if (val != Qnil) {
		int status;
		char *str;
		gRubyRunLevel++;
		val = rb_protect(rb_inspect, val, &status);
		gRubyRunLevel--;
		if (status != 0)
			return status;
		str = StringValuePtr(val);
		if (outValueString != NULL)
			*outValueString = strdup(str);
		MyAppCallback_showScriptMessage("%s", str);
	} else {
		if (outValueString != NULL)
			*outValueString = NULL;
	}
	return 0;
}

void
Ruby_showError(int status)
{
	static const int tag_raise = 6;
	char *msg = NULL, *msg2;
	VALUE val, backtrace;
	int interrupted = 0;
	if (status == tag_raise) {
		VALUE errinfo = rb_errinfo();
		VALUE eclass = CLASS_OF(errinfo);
		if (eclass == rb_eInterrupt) {
			msg = "Interrupt";
			interrupted = 1;
		}
	}
	gRubyRunLevel++;
	backtrace = rb_eval_string_protect("$backtrace = $!.backtrace.join(\"\\n\")", &status);
	if (msg == NULL) {
		val = rb_eval_string_protect("$!.to_s", &status);
		if (status == 0)
			msg = RSTRING_PTR(val);
		else msg = "(message not available)";
	}
	asprintf(&msg2, "%s\n%s", msg, RSTRING_PTR(backtrace));
	MyAppCallback_messageBox(msg2, (interrupted == 0 ? "Ruby script error" : "Ruby script interrupted"), 0, 3);
	free(msg2);
	gRubyRunLevel--;
}

void
Ruby_startup(void)
{
	VALUE val;
	
	/*  Initialize Ruby interpreter  */
	ruby_init();
	ruby_init_loadpath();
	ruby_script("MDRuby");
	
	/*  Define MDRuby classes  */
	MREventSetInitClass();
	MRCoreInitClass();
	MRSequenceInitClass();
	MRTrackInitClass();
	MRPointerInitClass();
	RubyDialogInitClass();
	
	/*  Create an object for standard output and standard error */
	val = rb_obj_alloc(rb_cObject);
	rb_define_singleton_method(val, "write", s_MessageOutput_Write, 1);
	rb_gv_set("$stdout", val);
	rb_gv_set("$stderr", val);
	
	/*  Global variable to hold error information  */
	rb_define_variable("$backtrace", &gRubyBacktrace);
	rb_define_variable("$error_history", &gRubyErrorHistory);
	gRubyErrorHistory = rb_ary_new();
	gRubyBacktrace = Qnil;
	
	/*  Register interrupt check code  */
	rb_add_event_hook(s_Event_Callback, RUBY_EVENT_ALL, Qnil);
	
	/*  Start interval timer  */
	s_SetIntervalTimer(0);
}
