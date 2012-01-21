/*
 *  MDRubyExtern.h
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 09/08/23.
 *  Copyright 2009-2012 Toshi Nagata. All rights reserved.
 *
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#ifndef __MDRubyExtern__
#define __MDRubyExtern__

#ifdef __cplusplus
extern "C" {
#endif

#define STUB extern

/*  This definition is intended to work around 'VALUE' type in sources without "ruby.h"  */
typedef void *RubyValue;
#define RubyNil (RubyValue)4
#define RubyFalse (RubyValue)0

extern void Ruby_startup(void);
extern void Ruby_showError(int status);
//extern RubyValue MDRuby_evalRubyScript(const char *script, int *status);
//extern RubyValue MDRuby_evalRubyScriptOnActiveDocumentWithInterrupt(const char *script, int *status);
extern int Ruby_callMethodOfDocument(const char *name, void *doc, int isSingleton, const char *argfmt,...);
extern RubyValue Ruby_evalRubyScriptOnDocument(const char *script, void *doc, int *status);
extern void Ruby_showRubyValue(RubyValue value);
extern int Ruby_methodType(const char *className, const char *methodName);

/*  Housekeeping "Document" type Ruby values  */
extern int MRSequenceRegister(void *myDocument);
extern int MRSequenceUnregister(void *myDocument);

void Ruby_getVersionStrings(const char **version, const char **copyright);
	
STUB const char *MyAppCallback_getGlobalSettings(const char *key);
STUB void MyAppCallback_setGlobalSettings(const char *key, const char *value);
STUB void MyAppCallback_saveGlobalSettings(void);
STUB int MyAppCallback_showScriptMessage(const char *fmt, ...);
STUB void MyAppCallback_setConsoleColor(int color);
STUB void MyAppCallback_showRubyPrompt(void);
STUB int MyAppCallback_checkInterrupt(void);
STUB int MyAppCallback_showProgressPanel(const char *msg);
STUB void MyAppCallback_hideProgressPanel(void);
STUB void MyAppCallback_setProgressValue(double dval);
STUB void MyAppCallback_setProgressMessage(const char *msg);
STUB void MyAppCallback_registerScriptMenu(const char *cmd, const char *title);
STUB RubyValue MyAppCallback_executeScriptFromFile(const char *path, int *status);
STUB int MyAppCallback_messageBox(const char *message, const char *title, int flags, int icon);

#ifdef __cplusplus
}
#endif

#endif /* __MDRubyExtern__ */
