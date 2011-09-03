//
//  MDRubyDialog.m
//  Alchemusica
//
//  Created by Toshi Nagata on 08/04/13.
//  Copyright 2008-2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#include "MDRuby.h"

static VALUE
	sTextSymbol, sTextFieldSymbol, sRadioSymbol, sButtonSymbol,
	sCheckBoxSymbol, sPopUpSymbol, sTextViewSymbol, sViewSymbol,
	sTagSymbol, sTypeSymbol,
	sTitleSymbol, sXSymbol, sYSymbol, sWidthSymbol, sHeightSymbol, 
	sOriginSymbol, sSizeSymbol, sFrameSymbol,
	sEnabledSymbol, sHiddenSymbol, sValueSymbol,
	sBlockSymbol, sRangeSymbol;

VALUE cMRDialog = Qfalse;

@implementation MDRubyDialogController

- (void)windowDidLoad
{
	[super windowDidLoad];
	ditems = [[NSMutableArray array] retain];
	[ditems addObject: [[[self window] contentView] viewWithTag: 0]];  /*  OK button  */
	[ditems addObject: [[[self window] contentView] viewWithTag: 1]];  /*  Cancel button  */
}

- (void)dealloc
{
	[ditems release];
	[super dealloc];
}

- (void)dialogItemAction: (id)sender
{
	int tag = [self searchDialogItem: sender];
	if (tag == 0)  /*  OK button  */
		[NSApp stopModal];
	else if (tag == 1)  /*  Cancel button  */
		[NSApp abortModal];
}

- (void)setRubyObject: (VALUE)val
{
	dval = val;
}

- (void)addDialogItem: (id)ditem
{
	[[[self window] contentView] addSubview: ditem];
	[ditems addObject: ditem];
}

- (id)dialogItemAtIndex: (int)index
{
	if (index >= 0 && index < [ditems count])
		return [ditems objectAtIndex: index];
	else return nil;
}

- (int)searchDialogItem: (id)ditem
{
	unsigned int ui = [ditems indexOfObjectIdenticalTo: ditem];
	if (ui == NSNotFound)
		return -1;
	else return ui;
}

- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
	VALUE items, item, val, val_min, val_max;
	int nitems, itag;
	NSString *s;

	if (dval == Qfalse)
		return NO;

	s = [control stringValue];
	items = rb_iv_get(dval, "_items");
	nitems = RARRAY_LEN(items);
	itag = [control tag];
	if (itag < 0 || itag >= nitems)
		return YES;  /*  Accept anything  */

	item = (RARRAY_PTR(items))[itag];
	val = rb_hash_aref(item, sRangeSymbol);
	if (NIL_P(val))
		return YES;  /*  Accept anything  */

	val_min = MDRuby_ObjectAtIndex(val, 0);
	val_max = MDRuby_ObjectAtIndex(val, 1);
	if (FIXNUM_P(val_min) && FIXNUM_P(val_max)) {
		int ival = [s intValue];
		int imin = NUM2INT(val_min);
		int imax = NUM2INT(val_max);
		if (ival < imin || ival > imax)
			return NO;
		[control setStringValue: [NSString stringWithFormat: @"%d", ival]];
	} else {
		double d = [s doubleValue];
		double dmin = NUM2DBL(val_min);
		double dmax = NUM2DBL(val_max);
		if (d < dmin || d > dmax)
			return NO;
	}
	return YES;
}

@end

#if 0
/*  Internal class for adding tags to a generic view  */
@interface MDRubyTaggedView : NSView {
	int tag;
}
- (void)setTag: (int)tag;
- (int)tag;
@end

@implementation MDRubyTaggedView
- (void)setTag: (int)aTag
{
	tag = aTag;
}
- (int)tag
{
	return tag;
}
@end;
#endif

#pragma mark ====== MRDialog alloc/init/release ======

typedef struct MRDialogInfo {
	MDRubyDialogController *d;
} MRDialogInfo;

static MDRubyDialogController *
s_MRDialog_GetController(VALUE self)
{
	MRDialogInfo *di;
	Data_Get_Struct(self, MRDialogInfo, di);
	if (di != NULL)
		return di->d;
	else return NULL;
}

static void
s_MRDialog_Release(void *p)
{
	if (p != NULL) {
		MDRubyDialogController *d = ((MRDialogInfo *)p)->d;
		if (d != nil) {
			[d setRubyObject: Qfalse]; /* Stop access to the Ruby object (in case the MDRubyDialogController is not dealloc'ed in the following line) */
			[d release];
			((MRDialogInfo *)p)->d = nil;
		}
		free(p);
	}
}

static VALUE
s_MRDialog_Alloc(VALUE klass)
{
	VALUE val;
	MRDialogInfo *di;
	MDRubyDialogController *d = [[MDRubyDialogController alloc] initWithWindowNibName: @"RubyDialog"];
	val = Data_Make_Struct(klass, MRDialogInfo, 0, s_MRDialog_Release, di);
	di->d = d;
	[d setRubyObject: val];
	return val;
}

static VALUE
s_MRDialog_Initialize(int argc, VALUE *argv, VALUE self)
{
	int i, j;
	VALUE val1;
	VALUE items;
	MDRubyDialogController *d = s_MRDialog_GetController(self);
	
	[d window];  // Load window

	rb_scan_args(argc, argv, "01", &val1);
	if (!NIL_P(val1)) {
		char *p = StringValuePtr(val1);
		[[d window] setTitle: [NSString stringWithUTF8String: p]];
	}

	//  Array of item informations
	items = rb_ary_new();
	
	//  Initialize "OK" and "Cancel" buttons (may be used for enabling/disabling buttons)
	for (i = 0; i < 2; i++) {
		VALUE item, vals[14];
		id button = [[[d window] contentView] viewWithTag: i];
		NSString *title = [button title];
		NSRect frame = [button frame];
		vals[0] = sTagSymbol;
		vals[1] = rb_str_new2(i == 0 ? "ok" : "cancel");
		vals[2] = sTypeSymbol;
		vals[3] = sButtonSymbol;
		vals[4] = sTitleSymbol;
		vals[5] = rb_str_new2([title UTF8String]);
		vals[6] = sXSymbol;
		vals[7] = rb_float_new(frame.origin.x);
		vals[8] = sYSymbol;
		vals[9] = rb_float_new(frame.origin.y);
		vals[10] = sWidthSymbol;
		vals[11] = rb_float_new(frame.size.width);
		vals[12] = sHeightSymbol;
		vals[13] = rb_float_new(frame.size.height);
		item = rb_hash_new();
		for (j = 0; j < 7; j++) {
			rb_hash_aset(item, vals[j * 2], vals[j * 2 + 1]);
		}
		rb_ary_push(items, item);
	}
	
	rb_iv_set(self, "_items", items);
	
	return Qnil;
}

#pragma mark ====== Ruby methods ======

static int
s_MRDialog_ItemIndexForTag(VALUE self, VALUE tag)
{
	VALUE items = rb_iv_get(self, "_items");
	int len = RARRAY_LEN(items);
	VALUE *ptr = RARRAY_PTR(items);
	int i;
	if (FIXNUM_P(tag) && (i = NUM2INT(tag)) >= 0 && i < len)
		return i;
	for (i = 0; i < len; i++) {
		if (rb_equal(tag, rb_hash_aref(ptr[i], sTagSymbol)) == Qtrue)
			return i;
	}
	rb_raise(rb_eStandardError, "MRDialog has no item with tag %s", StringValuePtr(tag));
	return -1; /* Not reached */
}

static NSString *
s_CleanUpNewLine(NSString *s)
{
	/*  Convert various "newline" characters in an NSString to "\n"  */
	unsigned int start, end, contentsEnd;
	NSRange range;
	NSMutableString *ms = [NSMutableString stringWithString: s];
	start = [ms length];
	while (start > 0) {
		/*  Get the "last line"  */
		range.location = start - 1;
		range.length = 1;
		[ms getLineStart: &start end: &end contentsEnd: &contentsEnd forRange: range];
		if (contentsEnd < end) {
			/*  Replace the EOL characters with @"\n"  */
			[ms replaceCharactersInRange: NSMakeRange(contentsEnd, end - contentsEnd) withString: @"\n"];
		}
	}
	return ms;
}

/*
 *  call-seq:
 *     dialog.set_attr(tag, hash)
 *
 *  Set the attributes given in the hash.
 */
static VALUE
s_MRDialog_SetAttr(VALUE self, VALUE tag, VALUE hash)
{
	int i;
	VALUE items = rb_iv_get(self, "_items");
	VALUE *ptr = RARRAY_PTR(items);
	int itag = s_MRDialog_ItemIndexForTag(self, tag);
	VALUE item = ptr[itag];
	VALUE type = rb_hash_aref(item, sTypeSymbol);
	MDRubyDialogController *d = s_MRDialog_GetController(self);
	id view = [d dialogItemAtIndex: itag];
	VALUE keys = rb_funcall(hash, rb_intern("keys"), 0);
	int klen = RARRAY_LEN(keys);
	VALUE *kptr = RARRAY_PTR(keys);
	
	for (i = 0; i < klen; i++) {
		VALUE key = kptr[i];
		VALUE val = rb_hash_aref(hash, key);
		BOOL flag;
		NSString *s;
		if (key == sRangeSymbol) {
			/*  Range of value (must be an array of two integers or two floats)  */
			VALUE val1, val2;
			double d1, d2;
			if (TYPE(val) != T_ARRAY || RARRAY_LEN(val) != 2)
				rb_raise(rb_eTypeError, "the attribute 'range' should specify an array of two numbers");
			val1 = RARRAY_PTR(val)[0];
			val2 = RARRAY_PTR(val)[1];
			d1 = NUM2DBL(val1);
			d2 = NUM2DBL(val2);
			if (!FIXNUM_P(val1) || !FIXNUM_P(val2)) {
				/*  Convert to a range of floats  */
				if (TYPE(val1) != T_FLOAT || TYPE(val2) != T_FLOAT) {
					val1 = rb_float_new(NUM2DBL(val1));
					val2 = rb_float_new(NUM2DBL(val2));
					val = rb_ary_new3(2, val1, val2);
				}
			}
			if (d1 > d2)
				rb_raise(rb_eArgError, "invalid number range [%g,%g]", d1, d2);
			rb_hash_aset(item, key, val);
		} else if (key == sValueSymbol) {
			/*  Value  */
			if (type == sTextFieldSymbol || type == sTextViewSymbol) {
				s = [NSString stringWithUTF8String: StringValuePtr(val)];
				if (type == sTextFieldSymbol)
					[view setStringValue: s];
				else
					[[view documentView] setString: s];
			} else if (type == sCheckBoxSymbol) {
				[view setState: (RTEST(val) ? NSOnState : NSOffState)];
			}
		} else if (key == sTitleSymbol) {
			/*  Title  */
			s = [NSString stringWithUTF8String: StringValuePtr(val)];
			if (type == sTextSymbol)
				[view setStringValue: s];
			else [view setTitle: s];
		} else if (key == sEnabledSymbol) {
			/*  Enabled  */
			flag = (val != Qnil && val != Qfalse);
			if (type == sTextViewSymbol)
				[[view documentView] setEditable: flag];
			else
				[view setEnabled: flag];
		} else if (key == sHiddenSymbol) {
			/*  Hidden  */
			flag = (val != Qnil && val != Qfalse);
			[view setHidden: flag];
		} else if (key == sXSymbol || key == sYSymbol || key == sWidthSymbol || key == sHeightSymbol) {
			/*  Frame components  */
			NSRect frame;
			float f = NUM2DBL(val);
			frame = [view frame];
			if (key == sXSymbol)
				frame.origin.x = f;
			else if (key == sYSymbol)
				frame.origin.y = f;
			else if (key == sWidthSymbol)
				frame.size.width = f;
			else
				frame.size.height = f;
			[view setFrame: frame];
		} else if (key == sOriginSymbol || key == sSizeSymbol) {
			/*  Frame components  */
			NSRect frame;
			float f0 = NUM2DBL(MDRuby_ObjectAtIndex(val, 0));
			float f1 = NUM2DBL(MDRuby_ObjectAtIndex(val, 1));
			frame = [view frame];
			if (key == sOriginSymbol) {
				frame.origin.x = f0;
				frame.origin.y = f1;
			} else {
				frame.size.width = f0;
				frame.size.height = f1;
			}
			[view setFrame: frame];			
		} else if (key == sFrameSymbol) {
			/*  Frame (x, y, width, height)  */
			NSRect frame;
			frame.origin.x = NUM2DBL(MDRuby_ObjectAtIndex(val, 0));
			frame.origin.y = NUM2DBL(MDRuby_ObjectAtIndex(val, 1));
			frame.size.width = NUM2DBL(MDRuby_ObjectAtIndex(val, 2));
			frame.size.height = NUM2DBL(MDRuby_ObjectAtIndex(val, 3));
			[view setFrame: frame];
		} else {
			rb_hash_aset(item, key, val);
		}
	}
	return Qnil;
}

/*
 *  call-seq:
 *     dialog.attr(tag, key)
 *
 *  Get the attribute for the key.
 */
static VALUE
s_MRDialog_Attr(VALUE self, VALUE tag, VALUE key)
{
	BOOL flag;
	VALUE items = rb_iv_get(self, "_items");
	VALUE *ptr = RARRAY_PTR(items);
	int itag = s_MRDialog_ItemIndexForTag(self, tag);
	VALUE item = ptr[itag];
	VALUE type = rb_hash_aref(item, sTypeSymbol);
	MDRubyDialogController *d = s_MRDialog_GetController(self);
	id view = [d dialogItemAtIndex: itag];
	
	VALUE val = Qnil;
	NSString *s;
	if (key == sValueSymbol) {
		/*  Value  */
		if (type == sTextFieldSymbol) {
			/*  Is range specified?  */
			VALUE range = rb_hash_aref(item, sRangeSymbol);
			s = [view stringValue];
			if (TYPE(range) == T_ARRAY) {
				if (FIXNUM_P((RARRAY_PTR(range))[0]))
					val = INT2NUM([s intValue]);
				else
					val = rb_float_new([s doubleValue]);
			} else val = rb_str_new2([s UTF8String]);
		} else if (type == sTextViewSymbol) {
			s = [[view documentView] string];
			s = s_CleanUpNewLine(s);
			val = rb_str_new2([s UTF8String]);
		} else if (type == sCheckBoxSymbol) {
			val = ([view state] == NSOnState ? Qtrue : Qfalse);
		}
	} else if (key == sTitleSymbol) {
		if (type == sTextSymbol)
			s = [view stringValue];
		else s = [view title];
		val = rb_str_new2([s UTF8String]);
	} else if (key == sEnabledSymbol) {
		/*  Enabled  */
		if (type == sTextViewSymbol)
			flag = [[view documentView] isEditable];
		else
			flag = [view isEnabled];
		val = (flag ? Qtrue : Qfalse);
	} else if (key == sHiddenSymbol) {
		/*  Hidden  */
		val = ([view isHiddenOrHasHiddenAncestor] ? Qtrue : Qfalse);
	} else if (key == sXSymbol || key == sYSymbol || key == sWidthSymbol || key == sHeightSymbol) {
		/*  Frame components  */
		NSRect frame;
		float f;
		frame = [view frame];
		if (key == sXSymbol)
			f = frame.origin.x;
		else if (key == sYSymbol)
			f = frame.origin.y;
		else if (key == sWidthSymbol)
			f = frame.size.width;
		else
			f = frame.size.height;
		val = rb_float_new(f);
	} else if (key == sOriginSymbol || key == sSizeSymbol) {
		/*  Frame components  */
		NSRect frame;
		float f0, f1;
		frame = [view frame];
		if (key == sOriginSymbol) {
			f0 = frame.origin.x;
			f1 = frame.origin.y;
		} else {
			f0 = frame.size.width;
			f1 = frame.size.height;
		}
		val = rb_ary_new3(2, rb_float_new(f0), rb_float_new(f1));
		rb_obj_freeze(val);
	} else if (key == sFrameSymbol) {
		/*  Frame (x, y, width, height)  */
		NSRect frame = [view frame];
		val = rb_ary_new3(4, rb_float_new(frame.origin.x), rb_float_new(frame.origin.y), rb_float_new(frame.size.width), rb_float_new(frame.size.height));
		rb_obj_freeze(val);
	} else {
		val = rb_hash_aref(item, key);
	}

	return val;
}

/*
 *  call-seq:
 *     dialog.run
 *
 *  Run the modal session for this dialog.
 */
static VALUE
s_MRDialog_Run(VALUE self)
{
	int retval;
	MDRubyDialogController *d = s_MRDialog_GetController(self);

	retval = [NSApp runModalForWindow: [d window]];
	[d close];
	if (retval == NSRunStoppedResponse) {
		VALUE items = rb_iv_get(self, "_items");
		int len = RARRAY_LEN(items);
		VALUE *ptr = RARRAY_PTR(items);
		VALUE hash = rb_hash_new();
		int i;
		/*  Get values for editable controls  */
		for (i = 0; i < len; i++) {
		//	VALUE type = rb_hash_aref(ptr[i], sTypeSymbol);
			VALUE tag = rb_hash_aref(ptr[i], sTagSymbol);
			VALUE val;
			if (NIL_P(tag))
				continue;
			val = s_MRDialog_Attr(self, tag, sValueSymbol);
			rb_hash_aset(hash, tag, val);
		}
		return hash;
	} else
		return Qfalse;
}

/*
 *  call-seq:
 *     dialog.layout(row, column, i11, ..., i1c, i21, ..., i2c, ..., ir1, ..., irc, options) => integer
 *
 *  Layout items in a table.
 *  Returns an integer that represents the NSView that wraps the items.
 */
static VALUE
s_MRDialog_Layout(int argc, VALUE *argv, VALUE self)
{
	VALUE rval, cval, nhash, items;
	int row, col, i, j, n, itag, nitems;
	MDRubyDialogController *d;
	float *widths, *heights;
	float f, fmin;
	NSSize *sizes;
	NSView *contentView;
	NSView *layoutView;
	NSSize contentMinSize;
	NSRect layoutFrame;
	float col_padding = 4.0;  /*  Padding between columns  */
	float row_padding = 4.0;  /*  Padding between rows  */
	float margin = 15.0;

	d = s_MRDialog_GetController(self);
	contentView = [[d window] contentView];
	contentMinSize = [[d window] contentMinSize];
	items = rb_iv_get(self, "_items");
	nitems = RARRAY_LEN(items);
	
	if (argc < 2)
		rb_raise(rb_eArgError, "wrong number of arguments (should be at least 2 but only %d given)", argc);

	rval = argv[0];
	cval = argv[1];
	row = NUM2INT(rval);
	col = NUM2INT(cval);
	if (row <= 0)
		rb_raise(rb_eRangeError, "number of rows (%d) must be a positive integer", row);
	if (col <= 0)
		rb_raise(rb_eRangeError, "number of columns (%d) must be a positive integer", col);

	/*  Allocate temporary storage  */
	sizes = (NSSize *)calloc(sizeof(NSSize), row * col);
	widths = (float *)calloc(sizeof(float), col);
	heights = (float *)calloc(sizeof(float), row);
	if (sizes == NULL || widths == NULL || heights == NULL)
		rb_raise(rb_eNoMemError, "out of memory during layout");
	
	/*  Get frame sizes  */
	for (i = 0; i < row; i++) {
		for (j = 0; j < col; j++) {
			n = 2 + i * col + j;
			if (n < argc && FIXNUM_P(argv[n])) {
				itag = FIX2INT(argv[n]);
				if (itag >= nitems)
					rb_raise(rb_eRangeError, "item tag (%d) is out of range (should be 0..%d)", itag, nitems - 1);
				sizes[n - 2] = [[d dialogItemAtIndex: itag] frame].size;
			}
		}
	}
	
	/*  Calculate required widths  */
	fmin = 0.0;
	for (j = 0; j < col; j++) {
		for (i = 0; i < row; i++) {
			for (n = j; n >= 0; n--) {
				f = sizes[i * col + n].width;
				if (f > 0.0) {
					f += (n > 0 ? widths[n - 1] : 0.0);
					break;
				}
			}
			if (fmin < f)
				fmin = f;
		}
		fmin += col_padding;
		widths[j] = fmin;
	}

	/*  Calculate required heights  */
	fmin = 0.0;
	for (i = 0; i < row; i++) {
		for (j = 0; j < col; j++) {
			for (n = i; n >= 0; n--) {
				f = sizes[n * col + j].height;
				if (f > 0.0) {
					f += (n > 0 ? heights[n - 1] : 0.0);
					break;
				}
			}
			if (fmin < f)
				fmin = f;
		}
		fmin += row_padding;
		heights[i] = fmin;
	}
	
	/*  Create a layout view  */
	layoutFrame.size.width = widths[col - 1];
	layoutFrame.size.height = heights[row - 1];
	layoutFrame.origin.x = margin;
	layoutFrame.origin.y = contentMinSize.height;
	layoutView = [[[NSView alloc] initWithFrame: layoutFrame] autorelease];

	/*  Move the subviews into the layout view  */
	for (i = 0; i < row; i++) {
		for (j = 0; j < col; j++) {
			n = 2 + i * col + j;
			if (n < argc && FIXNUM_P(argv[n]) && (itag = FIX2INT(argv[n])) < nitems) {
				NSPoint pt;
				NSView *subview = [d dialogItemAtIndex: itag];
				float offset;
				VALUE type = rb_hash_aref((RARRAY_PTR(items))[itag], sTypeSymbol);
				if (type == sTextSymbol)
					offset = 3.0;
				else offset = 0.0;
				pt.x = (j > 0 ? widths[j - 1] : 0.0) + col_padding * 0.5;
				pt.y = layoutFrame.size.height - (i > 0 ? heights[i - 1] : 0.0) - sizes[n - 2].height - row_padding * 0.5 - offset;
				[subview retain];
				[subview removeFromSuperview];
				[layoutView addSubview: subview];
				[subview setFrameOrigin: pt];
				[subview release];
			}
		}
	}
	
	free(sizes);
	free(widths);
	free(heights);
	
	/*  Create a new hash for the layout view and push to _items */
	nhash = rb_hash_new();
	rb_hash_aset(nhash, sTypeSymbol, sViewSymbol);
	rb_ary_push(items, nhash);

	/*  Tag for the layout view  */
	itag = RARRAY_LEN(items) - 1;

	/*  Resize the window  */
	{
		NSSize winSize;
		winSize.width = layoutFrame.size.width + margin * 2;
		if (winSize.width < contentMinSize.width)
			winSize.width = contentMinSize.width;
		winSize.height = layoutFrame.size.height + contentMinSize.height + margin;
		[[d window] setContentSize: winSize];
	}
	
	/*  Add to the window  */
	[d addDialogItem: layoutView];
	
	/*  Returns the integer tag  */
	return INT2NUM(itag);
}

/*
 *  call-seq:
 *     dialog.item(type, hash) => integer
 *
 *  Create a dialog item.
 *    type: one of the following symbols; :text, :textfield, :radio, :checkbox, :popup
 *    hash: attributes that can be set by set_attr
 *  Returns an integer that represents the item. (0 and 1 are reserved for "OK" and "Cancel")
 */
static VALUE
s_MRDialog_Item(int argc, VALUE *argv, VALUE self)
{
	int itag;  /*  Integer tag for NSControl  */
	id control;  /*  A view  */
	NSRect rect, brect;
	NSString *title;
	NSDictionary *attr;
	NSFont *font;
	VALUE type, hash, val, nhash, items;
	MDRubyDialogController *d;

	d = s_MRDialog_GetController(self);
	rb_scan_args(argc, argv, "11", &type, &hash);
	if (NIL_P(hash))
		hash = rb_hash_new();
	rect.size.width = rect.size.height = 1.0;
	rect.origin.x = rect.origin.y = 0.0;

	val = rb_hash_aref(hash, sTitleSymbol);
	if (!NIL_P(val)) {
		title = [NSString stringWithUTF8String: StringValuePtr(val)];
	} else {
		title = @"";
	}

	Check_Type(type, T_SYMBOL);
	
	if (type == sTextViewSymbol)
		font = [NSFont userFixedPitchFontOfSize: 0];
	else
		font = [NSFont systemFontOfSize: [NSFont smallSystemFontSize]];
	attr = [NSDictionary dictionaryWithObjectsAndKeys: font, NSFontAttributeName, nil];
	brect.origin.x = brect.origin.y = 0.0;
	brect.size = [title sizeWithAttributes: attr];
	brect.size.width += 8;

	/*  Set rect if specified  */
/*	val = rb_hash_aref(hash, sXSymbol);
	if (!NIL_P(val) && (dval = NUM2DBL(val)) > 0.0)
		rect.origin.x = dval;
	val = rb_hash_aref(hash, sYSymbol);
	if (!NIL_P(val) && (dval = NUM2DBL(val)) > 0.0)
		rect.origin.y = dval;
	val = rb_hash_aref(hash, sWidthSymbol);
	if (!NIL_P(val) && (dval = NUM2DBL(val)) > 0.0)
		rect.size.width = dval;
	val = rb_hash_aref(hash, sHeightSymbol);
	if (!NIL_P(val) && (dval = NUM2DBL(val)) > 0.0)
		rect.size.height = dval; */

	/*  Create a new hash for this item  */
	nhash = rb_hash_new();
	rb_hash_aset(nhash, sTypeSymbol, type);

	if (type == sTextSymbol || type == sTextFieldSymbol) {
		if (rect.size.height == 1.0)
			rect.size.height = brect.size.height;
		if (rect.size.width == 1.0)
			rect.size.width = brect.size.width;
		if (type == sTextFieldSymbol)
			rect.size.height += 5.0;
		control = [[[NSTextField alloc] initWithFrame: rect] autorelease];
		[control setStringValue: title];
		[control setFont: font];
		[control setDelegate: d];
		if (type == sTextSymbol) {
			[control setEditable: NO];
			[control setBezeled: NO];
			[control setBordered: NO];
			[control setDrawsBackground: NO];
		} else {
			[control setEditable: YES];
			[control setBezeled: YES];
			[control setDrawsBackground: YES];
		}
	} else if (type == sTextViewSymbol) {
		/*  An NSTextView included within an NSScrollView  */
		NSTextView *tv;
		NSSize contentSize;
		if (rect.size.height == 1.0)
			rect.size.height = brect.size.height;
		if (rect.size.width == 1.0)
			rect.size.width = 90;
		control = [[[NSScrollView alloc] initWithFrame: rect] autorelease];
		[control setHasVerticalScroller: YES];
		[control setHasHorizontalScroller: NO];
		[control setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
		[control setBorderType: NSBezelBorder];
		[[control verticalScroller] setControlSize: NSSmallControlSize];
		contentSize = [control contentSize];
		tv = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, contentSize.width, contentSize.height)] autorelease];
		[tv setMinSize: NSMakeSize(0.0, contentSize.height)];
		[tv setMaxSize: NSMakeSize(FLT_MAX, FLT_MAX)];
		[tv setVerticallyResizable: YES];
		[tv setHorizontallyResizable: NO];
		[tv setAutoresizingMask: NSViewWidthSizable];
		[[tv textContainer] setContainerSize: NSMakeSize(contentSize.width, FLT_MAX)];
		[[tv textContainer] setWidthTracksTextView: YES];
		[tv setFont: font];
	//	[control setDelegate: d];
		[tv setRichText: NO];
		[tv setSelectable: YES];
		[tv setEditable: YES];
		[control setDocumentView: tv];
	} else if (type == sCheckBoxSymbol) {
		if (rect.size.height == 1.0)
			rect.size.height = 14;
		if (rect.size.width == 1.0)
			rect.size.width = brect.size.width + 20;
		control = [[[NSButton alloc] initWithFrame: rect] autorelease];
		[control setButtonType: NSSwitchButton];
		[[control cell] setControlSize: NSSmallControlSize];
		[control setFont: font];
		[control setTitle: title];
	} else {
		rb_raise(rb_eStandardError, "item type :%s is not implemented", rb_id2name(SYM2ID(type)));
	}

	/*  Push to _items  */
	items = rb_iv_get(self, "_items");
	rb_ary_push(items, nhash);
	itag = RARRAY_LEN(items) - 1;

	/*  Add to the window  */
	[d addDialogItem: control];

	/*  Tag as a Ruby integer  */
	val = INT2NUM(itag);

	/*  Set attributes  */
	s_MRDialog_SetAttr(self, val, hash);

	return val;
}

/*
 *  call-seq:
 *     dialog._items => an array of hash
 *
 *  Returns an internal array of items. For debugging use only.
 */
static VALUE
s_MRDialog_Items(VALUE self)
{
	return rb_iv_get(self, "_items");
}

#pragma mark ====== Initialize class ======

void
MRDialogInitClass(void)
{
	if (cMRDialog != Qfalse)
		return;

	cMRDialog = rb_define_class("RubyDialog", rb_cObject);
	rb_define_alloc_func(cMRDialog, s_MRDialog_Alloc);
	rb_define_private_method(cMRDialog, "initialize", s_MRDialog_Initialize, -1);
	rb_define_method(cMRDialog, "run", s_MRDialog_Run, 0);
	rb_define_method(cMRDialog, "item", s_MRDialog_Item, -1);
	rb_define_method(cMRDialog, "layout", s_MRDialog_Layout, -1);
	rb_define_method(cMRDialog, "_items", s_MRDialog_Items, 0);
	rb_define_method(cMRDialog, "set_attr", s_MRDialog_SetAttr, 2);
	rb_define_method(cMRDialog, "attr", s_MRDialog_Attr, 2);

	{
		static VALUE *sTable1[] = { &sTextSymbol, &sTextFieldSymbol, &sRadioSymbol, &sButtonSymbol, &sCheckBoxSymbol, &sPopUpSymbol, &sTextViewSymbol, &sViewSymbol, &sTagSymbol, &sTypeSymbol, &sTitleSymbol, &sXSymbol, &sYSymbol, &sWidthSymbol, &sHeightSymbol, &sOriginSymbol, &sSizeSymbol, &sFrameSymbol, &sEnabledSymbol, &sHiddenSymbol, &sValueSymbol, &sBlockSymbol, &sRangeSymbol };
		static const char *sTable2[] = { "text", "textfield", "radio", "button", "checkbox", "popup", "textview", "view", "tag", "type", "title", "x", "y", "width", "height", "origin", "size", "frame", "enabled", "hidden", "value", "block", "range" };
		int i;
		for (i = 0; i < sizeof(sTable1) / sizeof(sTable1[0]); i++)
			*(sTable1[i]) = ID2SYM(rb_intern(sTable2[i]));
	}
}
