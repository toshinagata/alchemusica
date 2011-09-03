//
//  RubyDialogController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 08/04/13.
//  Copyright 2008-2011 Toshi Nagata. All rights reserved.
//
/*
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>

#include "RubyDialogController.h"
#include "MDRuby.h"

VALUE cMRDialog = Qfalse;

@implementation RubyDialogController

- (void)windowDidLoad
{
	[super windowDidLoad];
	ditems = [[NSMutableArray array] retain];
	[ditems addObject: [[[self window] contentView] viewWithTag: 0]];  /*  OK button  */
	[ditems addObject: [[[self window] contentView] viewWithTag: 1]];  /*  Cancel button  */
	gRubyDialogIsFlipped = 1;
}

- (void)dealloc
{
	[ditems release];
	[super dealloc];
}

- (void)dialogItemAction: (id)sender
{
	RubyDialog_doItemAction(dval, (RDItem *)sender);

//	int tag = [self searchDialogItem: sender];
//	if (tag == 0)  /*  OK button  */
//		[NSApp stopModal];
//	else if (tag == 1)  /*  Cancel button  */
//		[NSApp abortModal];
}

- (void)setRubyObject: (RubyValue)val
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
	if (dval == NULL)
		return NO;
	return (RubyDialog_validateItemContent(dval, (RDItem *)control, [[fieldEditor string] UTF8String]) != 0);
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
	unichar ch;
	NSEvent *currentEvent = [NSApp currentEvent];
	if (dval == NULL)
		return;
	if ([currentEvent type] == NSKeyDown && ((ch = [[currentEvent charactersIgnoringModifiers] characterAtIndex:0]) == NSNewlineCharacter || ch == NSEnterCharacter))
		return;
	/*  Send action  */
	id obj = [aNotification object];
	[obj sendAction:[obj action] to:[obj target]];
}

@end

#pragma mark ====== Plain C Interface ======

RubyDialog *
RubyDialogCallback_new(void)
{
	RubyDialogController *cont = [[RubyDialogController alloc] initWithWindowNibName: @"RubyDialog"];
	[[cont window] orderOut: nil];
	return (RubyDialog *)cont;
}

void
RubyDialogCallback_release(RubyDialog *dref)
{
	RubyDialogController *cont = (RubyDialogController *)dref;
	[cont close];
	[cont release];
}

void
RubyDialogCallback_setRubyObject(RubyDialog *dref, RubyValue val)
{
	[(RubyDialogController *)dref setRubyObject: val];
}

void
RubyDialogCallback_setWindowTitle(RubyDialog *dref, const char *title)
{
	[[(RubyDialogController *)dref window] setTitle: [NSString stringWithUTF8String: title]];
}

int
RubyDialogCallback_runModal(RubyDialog *dref)
{
	RubyDialogController *cont = (RubyDialogController *)dref;
	[[cont window] makeKeyAndOrderFront: nil];
	if ([NSApp runModalForWindow: [cont window]] == NSRunStoppedResponse)
		return 0;  /*  OK  */
	else return 1;  /*  Cancel  */
}

void
RubyDialogCallback_endModal(RubyDialog *dref, int status)
{
	[NSApp stopModalWithCode: (status == 0 ? NSRunStoppedResponse : NSRunAbortedResponse)];
}

void
RubyDialogCallback_close(RubyDialog *dref)
{
	[(RubyDialogController *)dref close];
}

static inline RDRect
RDRectFromNSRect(NSRect frame)
{
	RDRect rframe;
	rframe.origin.x = frame.origin.x;
	rframe.origin.y = frame.origin.y;
	rframe.size.width = frame.size.width;
	rframe.size.height = frame.size.height;
	return rframe;
}

static inline NSRect
NSRectFromRDRect(RDRect rframe)
{
	return NSMakeRect(rframe.origin.x, rframe.origin.y, rframe.size.width, rframe.size.height);
}

static inline RDSize
RDSizeFromNSSize(NSSize size)
{
	RDSize rsize;
	rsize.width = size.width;
	rsize.height = size.height;
	return rsize;
}

static inline NSRect
sConvertForViewFromRDRect(RDItem *item, RDRect rframe)
{
	/*  Take care of the flipped view  */
	NSRect rect, superrect;
	NSView *superview = [(NSView *)item superview];
	if (superview == nil)
		return NSRectFromRDRect(rframe);
	superrect = [superview frame];
	rect.origin.x = rframe.origin.x;
	rect.size.width = rframe.size.width;
	rect.origin.y = superrect.size.height - rframe.size.height - rframe.origin.y;
	rect.size.height = rframe.size.height;
	return rect;
}

RDSize
RubyDialogCallback_windowMinSize(RubyDialog *dref)
{
	return RDSizeFromNSSize([[(RubyDialogController *)dref window] minSize]);
}

void
RubyDialogCallback_setWindowSize(RubyDialog *dref, RDSize size)
{
	NSWindow *win = [(RubyDialogController *)dref window];
	NSSize nsize;
	nsize.width = size.width;
	nsize.height = size.height;
	[win setContentSize: nsize];
	[win center];
/*	NSRect frame = [win frame];
	frame.size.width = size.width;
	frame.size.height = size.height;
	[win setFrame: frame display: YES];
	[win center]; */
}

void
RubyDialogCallback_createStandardButtons(RubyDialog *dref, const char *oktitle, const char *canceltitle)
{
	RubyDialogController *cont = (RubyDialogController *)dref;
	id okButton = [cont dialogItemAtIndex: 0];
	id cancelButton = [cont dialogItemAtIndex: 1];
	if (oktitle != NULL && oktitle[0] != 0)
		[okButton setTitle: [NSString stringWithUTF8String: oktitle]];
	else [okButton setHidden: YES];
	if (canceltitle != NULL && canceltitle[0] != 0)
		[cancelButton setTitle: [NSString stringWithUTF8String: canceltitle]];
	else [cancelButton setHidden: YES];
}

static NSRect
OffsetForItemRect(const char *type)
{
	NSRect offset = NSMakeRect(0, 0, 0, 0);
	if (strcmp(type, "textfield") == 0)
		offset.size.height = 5;
	else if (strcmp(type, "button") == 0) {
		offset.size.width = 24;
		offset.size.height = 14;
	}
	return offset;
}

RDItem *
RubyDialogCallback_createItem(RubyDialog *dref, const char *type, const char *title, RDRect frame)
{
	NSView *view = nil;
	NSRect rect, offset;
	RubyDialogController *cont = ((RubyDialogController *)dref);
	NSString *tstr = (title ? [NSString stringWithUTF8String: title] : nil);
	NSFont *font;
	font = [NSFont systemFontOfSize: [NSFont smallSystemFontSize]];
	
	rect = NSRectFromRDRect(frame);
	if (rect.size.width == 0.0)
		rect.size.width = 1.0;
	if (rect.size.height == 0.0)
		rect.size.height = 1.0;
	
	offset = OffsetForItemRect(type);
	
	if (strcmp(type, "text") == 0 || strcmp(type, "textfield") == 0) {
		/*  Static text or editable text field */
		NSTextField *tf;
		BOOL isTextField = (type[4] == 'f');
		tf = [[[NSTextField alloc] initWithFrame: rect] autorelease];
		[tf setStringValue: tstr];
		[tf setFont: font];
		[tf setDelegate: cont];
		if (isTextField) {
			[tf setEditable: YES];
			[tf setBezeled: YES];
			[tf setDrawsBackground: YES];
			[tf setDelegate:cont];
		} else {			
			[tf setEditable: NO];
			[tf setBezeled: NO];
			[tf setBordered: NO];
			[tf setDrawsBackground: NO];
			[tf sizeToFit];
		}
		view = tf;
	} else if (strcmp(type, "textview") == 0) {
		/*  Text view  */
		NSScrollView *sv;
		NSTextView *tv;
		NSSize contentSize;
		sv = [[[NSScrollView alloc] initWithFrame: rect] autorelease];
		[sv setHasVerticalScroller: YES];
		[sv setHasHorizontalScroller: NO];
		[sv setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
		[sv setBorderType: NSBezelBorder];
		[[sv verticalScroller] setControlSize: NSSmallControlSize];
		contentSize = [sv contentSize];
		tv = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, contentSize.width, contentSize.height)] autorelease];
		[tv setMinSize: NSMakeSize(0.0, contentSize.height)];
		[tv setMaxSize: NSMakeSize(FLT_MAX, FLT_MAX)];
		[tv setVerticallyResizable: YES];
		[tv setHorizontallyResizable: NO];
		[tv setAutoresizingMask: NSViewWidthSizable];
		[[tv textContainer] setContainerSize: NSMakeSize(contentSize.width, FLT_MAX)];
		[[tv textContainer] setWidthTracksTextView: YES];
		font = [NSFont userFixedPitchFontOfSize: 0];
		[tv setFont: font];
		//	[control setDelegate: d];
		[tv setRichText: NO];
		[tv setSelectable: YES];
		[tv setEditable: YES];
		[sv setDocumentView: tv];
		view = sv;
	} else if (strcmp(type, "view") == 0) {
		/*  Panel  */
		view = [[[NSView alloc] initWithFrame: rect] autorelease];
	} else if (strcmp(type, "button") == 0) {
		/*  Button  */
		NSButton *bn = [[[NSButton alloc] initWithFrame: rect] autorelease];
		[bn setButtonType: NSMomentaryPushInButton];
		[bn setBezelStyle: NSRoundedBezelStyle];
		[[bn cell] setControlSize: NSSmallControlSize];
		[bn setFont: font];
		[bn setTitle: tstr];
		[bn sizeToFit];
		view = bn;
	} else if (strcmp(type, "popup") == 0) {
		/*  Popup button (wxChoice)  */
		NSPopUpButton *pn = [[[NSPopUpButton alloc] initWithFrame: rect] autorelease];
		[[pn cell] setControlSize: NSSmallControlSize];
		[pn setFont: font];
		view = pn;
	} else if (strcmp(type, "checkbox") == 0) {
		NSButton *bn = [[[NSButton alloc] initWithFrame: rect] autorelease];
		[bn setButtonType: NSSwitchButton];
		[[bn cell] setControlSize: NSSmallControlSize];
		[bn setFont: font];
		[bn setTitle: tstr];
		[bn sizeToFit];
		view = bn;
	} else if (strcmp(type, "radio") == 0) {
		NSButton *bn = [[[NSButton alloc] initWithFrame: rect] autorelease];
		[bn setButtonType: NSRadioButton];
		[[bn cell] setControlSize: NSSmallControlSize];
		[bn setFont: font];
		[bn setTitle: tstr];
		[bn sizeToFit];
		view = bn;
	} else return NULL;
	
	{  /*  Resize the frame rect  */
		RDSize minSize = RubyDialogCallback_sizeOfString((RDItem *)view, title);
		minSize.width += offset.size.width;
		minSize.height += offset.size.height;
		rect = [view frame];
		if (rect.size.height < minSize.height)
			rect.size.height = minSize.height;
		if (rect.size.width < minSize.width)
			rect.size.width = minSize.width;
		[view setFrame: rect];  /*  For flipped coordinate system (like Cocoa), the y-coordinate will need update after being added to the superview */
	}
	
	[cont addDialogItem: view];
	if ([view respondsToSelector: @selector(setAction:)]) {
		[(id)view setAction: @selector(dialogItemAction:)];
		[(id)view setTarget: cont];
	}
	if (gRubyDialogIsFlipped) {
		/*  Update the y coordinate  */
		NSRect superRect = [[view superview] frame];
		rect.origin.y = superRect.size.height - rect.size.height - rect.origin.y;
		[view setFrame: rect];
	}

	return (RDItem *)view;
}

RDItem *
RubyDialogCallback_dialogItemAtIndex(RubyDialog *dref, int idx)
{
	if (idx == -1)
		return (RDItem *)[[(RubyDialogController *)dref window] contentView];
	else return (RDItem *)[(RubyDialogController *)dref dialogItemAtIndex: idx];
}

int
RubyDialogCallback_indexOfItem(RubyDialog *dref, RDItem *item)
{
	return [(RubyDialogController *)dref searchDialogItem: (id)item];
}

void
RubyDialogCallback_moveItemUnderView(RDItem *item, RDItem *superView, RDPoint origin)
{
	if (item == NULL || superView == NULL || item == superView)
		return;
	[(NSView *)item removeFromSuperview];
	[(NSView *)superView addSubview: (NSView *)item];
	if (gRubyDialogIsFlipped) {
		NSRect rect = [(NSView *)item frame];
		NSRect superRect = [(NSView *)superView frame];
		origin.y = superRect.size.height - rect.size.height - origin.y;
	}
	[(NSView *)item setFrameOrigin: NSMakePoint(origin.x, origin.y)];
}

RDItem *
RubyDialogCallback_superview(RDItem *item)
{
	return (RDItem *)[(NSView *)item superview];
}

RDRect
RubyDialogCallback_frameOfItem(RDItem *item)
{
	NSRect rect = [(NSView *)item frame];
	if (gRubyDialogIsFlipped) {
		NSView *superview = [(NSView *)item superview];
		if (superview != nil) {
			NSRect superRect = [superview frame];
			rect.origin.y = superRect.size.height - rect.size.height - rect.origin.y;
		}
	}
	return RDRectFromNSRect(rect);
}

void
RubyDialogCallback_setFrameOfItem(RDItem *item, RDRect rect)
{
	NSRect wrect = NSRectFromRDRect(rect);
	if (gRubyDialogIsFlipped) {
		NSView *superview = [(NSView *)item superview];
		if (superview != NULL) {
			NSRect srect = [superview frame];
			wrect.origin.y = srect.size.height - wrect.size.height - wrect.origin.y;
		}
	}
	[(NSView *)item setFrame: wrect];
}

void
RubyDialogCallback_setStringToItem(RDItem *item, const char *s)
{
	NSView *view = (NSView *)item;
	NSString *str = [NSString stringWithUTF8String: s];
	if ([view isKindOfClass: [NSTextView class]]) {
		[(NSTextView *)view setString: str];
	} else if ([view respondsToSelector: @selector(setStringValue:)]) {
		[(id)view setStringValue: str];
	}
}

void
RubyDialogCallback_getStringFromItem(RDItem *item, char *buf, int bufsize)
{
	NSView *view = (NSView *)item;
	NSString *str;
	if ([view isKindOfClass: [NSTextView class]]) {
		str = [(NSTextView *)view string];
	} else if ([view respondsToSelector: @selector(stringValue:)]) {
		str = [(id)view stringValue];
	} else {
		buf[0] = 0;
		return;
	}
	snprintf(buf, bufsize, "%s", [str UTF8String]);
}

char *
RubyDialogCallback_getStringPtrFromItem(RDItem *item)
{
	NSView *view = (NSView *)item;
	NSString *str;
	if ([view isKindOfClass: [NSTextView class]]) {
		str = [(NSTextView *)view string];
	} else if ([view respondsToSelector: @selector(stringValue)]) {
		str = [(id)view stringValue];
	} else return NULL;
	return strdup([str UTF8String]);
}

char *
RubyDialogCallback_titleOfItem(RDItem *item)
{
	NSString *str;
	NSView *view = (NSView *)item;
	if ([view isKindOfClass: [NSTextField class]]) {
		str = [(NSTextField *)view stringValue];
	} else if ([view respondsToSelector: @selector(title)]) {
		str = [(id)view title];
	} else return NULL;
	return strdup([str UTF8String]);
}

void
RubyDialogCallback_setTitleToItem(RDItem *item, const char *s)
{
	NSString *str = [NSString stringWithUTF8String: s];
	NSView *view = (NSView *)item;
	if ([view isKindOfClass: [NSTextField class]]) {
		[(NSTextField *)view setStringValue: str];
	} else if ([view respondsToSelector: @selector(setTitle:)]) {
		[(id)view setTitle: str];
	}
}

void
RubyDialogCallback_setEnabledForItem(RDItem *item, int flag)
{
	NSView *view = (NSView *)item;
	if ([view isKindOfClass: [NSTextView class]]) {
		[(NSTextView *)view setEditable: (flag != 0)];
	} else if ([view respondsToSelector: @selector(setEnabled:)]) {
		[(id)view setEnabled: (flag != 0)];
	}
}

int
RubyDialogCallback_isItemEnabled(RDItem *item)
{
	NSView *view = (NSView *)item;
	if ([view isKindOfClass: [NSTextView class]]) {
		return [(NSTextView *)view isEditable];
	} else if ([view respondsToSelector: @selector(isEnabled)]) {
		return [(id)view isEnabled];
	} else return 0;
}

void
RubyDialogCallback_setHiddenForItem(RDItem *item, int flag)
{
	[(NSView *)item setHidden: (flag != 0)];
}

int
RubyDialogCallback_isItemHidden(RDItem *item)
{
	return [(NSView *)item isHidden];
}

void
RubyDialogCallback_setEditableForItem(RDItem *item, int flag)
{
	RubyDialogCallback_setEnabledForItem(item, flag);
}

int
RubyDialogCallback_isItemEditable(RDItem *item)
{
	return RubyDialogCallback_isItemEnabled(item);
}

void
RubyDialogCallback_setStateForItem(RDItem *item, int state)
{
	if ([(id)item isKindOfClass:[NSButton class]])
		[(NSButton *)item setState:(state ? NSOnState : NSOffState)];
}

int
RubyDialogCallback_getStateForItem(RDItem *item)
{
	if ([(id)item isKindOfClass:[NSButton class]])
		return [(NSButton *)item state] == NSOnState ? 1 : 0;
	else return 0;
}

void
RubyDialogCallback_setNeedsDisplay(RDItem *item, int flag)
{
	[(NSView *)item setNeedsDisplay:flag];
}

int
RubyDialogCallback_countSubItems(RDItem *item)
{
	if ([(NSView *)item respondsToSelector: @selector(numberOfItems)]) {
		return [(id)item numberOfItems];
	} else return 0;
}

int
RubyDialogCallback_appendSubItem(RDItem *item, const char *s)
{
	if ([(NSView *)item isKindOfClass: [NSPopUpButton class]]) {
		NSMenu *menu = [(NSPopUpButton *)item menu];
		id menuItem = [menu addItemWithTitle: [NSString stringWithUTF8String: s] action: nil keyEquivalent: @""];
		return [menu indexOfItem: menuItem];
	} else return -1;
}

int
RubyDialogCallback_insertSubItem(RDItem *item, const char *s, int pos)
{
	if ([(NSView *)item isKindOfClass: [NSPopUpButton class]]) {
		NSMenu *menu = [(NSPopUpButton *)item menu];
		id menuItem = [menu insertItemWithTitle: [NSString stringWithUTF8String: s] action: nil keyEquivalent: @"" atIndex: pos];
		return [menu indexOfItem: menuItem];
	} else return -1;
}

int
RubyDialogCallback_deleteSubItem(RDItem *item, int pos)
{	
	if ([(NSView *)item isKindOfClass: [NSPopUpButton class]]) {
		NSPopUpButton *p = (NSPopUpButton *)item;
		if (pos >= 0 && pos < [p numberOfItems]) {
			[p removeItemAtIndex: pos];
			return pos;
		}
	}
	return -1;
}

char *
RubyDialogCallback_titleOfSubItem(RDItem *item, int pos)
{
	if ([(NSView *)item isKindOfClass: [NSPopUpButton class]]) {
		NSPopUpButton *p = (NSPopUpButton *)item;
		if (pos >= 0 && pos < [p numberOfItems]) {
			NSString *str = [p itemTitleAtIndex: pos];
			return strdup([str UTF8String]);
		}
	}
	return NULL;
}

void
RubyDialogCallback_setSelectedSubItem(RDItem *item, int pos)
{
	if ([(NSView *)item isKindOfClass: [NSPopUpButton class]]) {
		NSPopUpButton *p = (NSPopUpButton *)item;
		if (pos >= 0 && pos < [p numberOfItems]) {
			[p selectItemAtIndex: pos];
		}
	}
}

int
RubyDialogCallback_selectedSubItem(RDItem *item)
{
	if ([(NSView *)item isKindOfClass: [NSPopUpButton class]]) {
		return [(NSPopUpButton *)item indexOfSelectedItem];
	}
	return -1;
}

RDSize
RubyDialogCallback_sizeOfString(RDItem *item, const char *s)
{
	if ([(NSView *)item respondsToSelector: @selector(font)]) {
		NSFont *font = [(id)item font];
		NSString *str = [NSString stringWithUTF8String: s];
		NSDictionary *attr = [NSDictionary dictionaryWithObjectsAndKeys: font, NSFontAttributeName, nil];
		NSSize size = [str sizeWithAttributes: attr];
		return RDSizeFromNSSize(size);
	} else {
		RDSize zeroSize = {0, 0};
		return zeroSize;
	}
}

RDSize
RubyDialogCallback_resizeToBest(RDItem *item)
{
	NSSize size;
	if ([(NSView *)item respondsToSelector: @selector(sizeToFit)]) {
		[(id)item sizeToFit];
	}
	size = [(NSView *)item frame].size;
	return RDSizeFromNSSize(size);
}

int
RubyDialogCallback_savePanel(const char *title, const char *dirname, const char *wildcard, char *buf, int bufsize)
{
	int result;
	NSSavePanel *panel = [NSSavePanel savePanel];
	NSString *dirstr = (dirname != NULL ? [NSString stringWithUTF8String: dirname] : nil);
	[panel setTitle: [NSString stringWithUTF8String: title]];
	result = [panel runModalForDirectory: dirstr file: [NSString stringWithUTF8String: buf]];
	if (result == NSFileHandlingPanelOKButton) {
		strncpy(buf, [[panel filename] UTF8String], bufsize - 1);
		buf[bufsize - 1] = 0;
		result = 1;
	} else {
		buf[0] = 0;
		result = 0;
	}
	[panel close];
	return result;
}

int
RubyDialogCallback_openPanel(const char *title, const char *dirname, const char *wildcard, char ***array, int for_directories, int multiple_selection)
{
	int result = 0;
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	NSString *dirstr = (dirname != NULL ? [NSString stringWithUTF8String: dirname] : nil);
	[panel setTitle: [NSString stringWithUTF8String: title]];
	if (for_directories) {
		[panel setCanChooseFiles: NO];
		[panel setCanChooseDirectories: YES];
	}
	result = [panel runModalForDirectory: dirstr file: nil types: nil];
	if (result == NSOKButton) {
		NSArray *names = [panel filenames];
		int n = [names count];
		int i;
		*array = (char **)malloc(sizeof(char *) * n);
		for (i = 0; i < n; i++) {
			(*array)[i] = strdup([[names objectAtIndex: i] UTF8String]);
		}
		result = n;
	} else result = 0;
	[panel close];
	return result;
}
