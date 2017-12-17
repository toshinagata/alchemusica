//
//  RubyDialogController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 08/04/13.
//  Copyright 2008-2016 Toshi Nagata. All rights reserved.
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
	NSView *contentView;
	[super windowDidLoad];
	autoResizeEnabled = YES;
	ditems = [[NSMutableArray array] retain];
	[ditems addObject: [[[self window] contentView] viewWithTag: 0]];  /*  OK button  */
	[ditems addObject: [[[self window] contentView] viewWithTag: 1]];  /*  Cancel button  */
	gRubyDialogIsFlipped = 1;
	contentView = [[self window] contentView];
	[contentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[contentView setAutoresizesSubviews:NO];
	mySize = [[[self window] contentView] frame].size;
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidResize:)
												 name:NSWindowDidResizeNotification object:[self window]];
}

- (void)dealloc
{
	if (myTimer != nil)
		[myTimer invalidate];
	[ditems release];
	[super dealloc];
}

- (void)dialogItemAction: (id)sender
{
	RubyDialog_doItemAction(dval, (RDItem *)sender, 0);

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
	NSUInteger ui = [ditems indexOfObjectIdenticalTo: ditem];
	if (ui == NSNotFound)
		return -1;
	else return (int)ui;
}

- (void)timerCallback:(NSTimer *)theTimer
{
	RubyDialog_doTimerAction((RubyValue)dval);
}

- (int)startIntervalTimer: (float)millisec
{
	if (myTimer != nil)
		[myTimer invalidate];
	myTimer = [NSTimer scheduledTimerWithTimeInterval:millisec / 1000.0 target:self selector:@selector(timerCallback:) userInfo:nil repeats:YES];
	return 1;
}

- (void)stopIntervalTimer
{
	if (myTimer != nil) {
		[myTimer invalidate];
		myTimer = nil;
	}
}

- (void)cancel:(id)sender
{
	//  Send action for the "cancel" button
	id ditem;
	//  If we are editing a text view, then ignore ESC or control-period
	if ([[[self window] firstResponder] isKindOfClass:[NSTextView class]])
		return;
	ditem = [self dialogItemAtIndex:1];
	if (ditem != nil && ![ditem isHidden] && [ditem isEnabled])
		RubyDialog_doItemAction(dval, (RDItem *)ditem, 0);
}

- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
	if (dval == NULL)
		return NO;
	return (RubyDialog_validateItemContent(dval, (RDItem *)control, [[fieldEditor string] UTF8String]) != 0);
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
	if (dval == NULL)
		return;
	/*  Send action  */
	id obj = [aNotification object];
	[obj sendAction:[obj action] to:[obj target]];
	if ([obj isKindOfClass:[NSTextField class]] && [self searchDialogItem:obj] >= 0) {
		//  User-defined text field
		id movementCode = [[aNotification userInfo] objectForKey:@"NSTextMovement"];
		if (movementCode != nil && [movementCode intValue] == NSReturnTextMovement) {
			//  Return key is pressed
			//  Send key event to the window (to process default button)
			//  See the Cocoa documentation for -[NSTextField textDidEndEditing:]
			[[self window] performKeyEquivalent:[NSApp currentEvent]];
		}
	}
}

- (void)textDidChange:(NSNotification *) aNotification
{
	id view = [[aNotification object] enclosingScrollView];
	[self dialogItemAction:view];
}

static void
sResizeSubViews(RubyValue dval, NSView *view, int dx, int dy)
{
	NSArray *subviews = [view subviews];
	int idx, n = (int)[subviews count];
	for (idx = 0; idx < n; idx++) {
		int i, d, f, d1, d2, d3, ddx, ddy;
		NSView *current = [subviews objectAtIndex:idx];
		NSRect frame = [current frame];
		int flex = RubyDialog_getFlexFlags(dval, (RDItem *)current);
		if (flex < 0)
			continue;		
		for (i = 0, f = flex; i < 2; i++, f /= 2) {
			if (i == 0)
				d = dx;
			else
				d = dy;
			switch (f & 21) {  /*  left, right, width (or top, bottom, height) */
				case 21:  /*  all flex  */
					d1 = d2 = d / 3;
					d3 = d - d1 - d2;
					break;
				case 5:   /*  left & right  */
					d1 = d / 2;
					d2 = 0;
					d3 = d - d1;
					break;
				case 17:  /*  left & width  */
					d1 = d / 2;
					d2 = d - d1;
					d3 = 0;
					break;
				case 20:  /*  right & width  */
					d1 = 0;
					d2 = d / 2;
					d3 = d - d2;
					break;
				case 1:   /*  left  */
					d1 = d;
					d2 = d3 = 0;
					break;
				case 4:   /*  right */
					d3 = d;
					d1 = d2 = 0;
					break;
				case 16:  /*  width  */
					d2 = d;
					d1 = d3 = 0;
					break;
				default:  /*  no resize  */
					d1 = d2 = d3 = 0;
					break;
			}
			if (i == 0) {
				frame.origin.x += d1;
				frame.size.width += d2;
				ddx = d2;
			} else {
				frame.origin.y += (gRubyDialogIsFlipped ? d3 : d1);
				frame.size.height += d2;
				ddy = d2;
			}
		}
		if (ddx != 0 || ddy != 0)
			sResizeSubViews(dval, current, ddx, ddy);
		[current setFrame:frame];
	}
}

- (void)windowDidResize:(NSNotification *)notification
{
	NSSize size = [[self window] frame].size;
	if (mySize.width != 0 && mySize.height != 0 && autoResizeEnabled) {
		/*  Resize the subviews  */
		sResizeSubViews((RubyValue)dval, [[self window] contentView], size.width - mySize.width, size.height - mySize.height);
	}
	mySize.width = size.width;
	mySize.height = size.height;
}

#pragma mark ====== TableView data source protocol ======

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return RubyDialog_GetTableItemCount((RubyValue)dval, (RDItem *)[aTableView enclosingScrollView]);
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	char buf[1024];
	int column = (int)[[aTableView tableColumns] indexOfObject:aTableColumn];
	RubyDialog_GetTableItemText((RubyValue)dval, (RDItem *)[aTableView enclosingScrollView], (int)rowIndex, column, buf, sizeof buf);
	return [NSString stringWithUTF8String:buf];
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	int column = (int)[[aTableView tableColumns] indexOfObject:aTableColumn];
	RubyDialog_SetTableItemText((RubyValue)dval, (RDItem *)[aTableView enclosingScrollView], (int)rowIndex, column, [anObject UTF8String]);
}

@end

#pragma mark ====== Plain C Interface ======

RubyValue
RubyDialogCallback_parentModule(void)
{
	return RubyFalse;
}

RubyDialog *
RubyDialogCallback_new(int style)
{
	NSRect rect = NSMakeRect(390, 382, 220, 55);
	NSWindow *win;
	int mask = NSTitledWindowMask;

	//  Window style
	if (style & rd_Resizable)
		mask |= NSResizableWindowMask;
	if (style & rd_HasCloseBox)
		mask |= NSClosableWindowMask | NSMiniaturizableWindowMask;

	win = [[NSWindow alloc] initWithContentRect:rect
			styleMask:mask
			backing:NSBackingStoreBuffered defer:YES];

	//	RubyDialogController *cont = [[RubyDialogController alloc] initWithWindowNibName: @"RubyDialog"];

	RubyDialogController *cont = [[RubyDialogController alloc] initWithWindow:win];
	cont->style = style;

	{
		/*  Create OK/Cancel buttons  */
		int i;
		for (i = 0; i < 2; i++) {
			if (i == 0) {
				rect = NSMakeRect(125, 13, 80, 28);
			} else {
				rect = NSMakeRect(15, 13, 80, 28);
			}
			NSButton *bn = [[[NSButton alloc] initWithFrame: rect] autorelease];
			[bn setButtonType: NSMomentaryPushInButton];
			[bn setBezelStyle: NSRoundedBezelStyle];
			[[bn cell] setControlSize: NSSmallControlSize];
			[bn setTag:i];
			[bn setTitle: (i == 0 ? @"OK" : @"Cancel")];
			[bn setAction: @selector(dialogItemAction:)];
			[bn setTarget: cont];
			[[win contentView] addSubview:bn];
		}
	}
	
	[cont windowDidLoad];
	[win autorelease];
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
	int status;
	if (cont->style & rd_HasCloseBox)
		return -1;  /*  Cannot run  */
	[[cont window] makeKeyAndOrderFront: nil];
	cont->isModal = YES;
	status = (int)[NSApp runModalForWindow: [cont window]];
	cont->isModal = NO;
	if (status == NSRunStoppedResponse)
		return 0;  /*  OK  */
	else return 1;  /*  Cancel  */
}

void
RubyDialogCallback_endModal(RubyDialog *dref, int status)
{
	[NSApp stopModalWithCode: (status == 0 ? NSRunStoppedResponse : NSRunAbortedResponse)];
}

int
RubyDialogCallback_isModal(RubyDialog *dref)
{
	return ((RubyDialogController *)dref)->isModal;
}

void
RubyDialogCallback_destroy(RubyDialog *dref)
{
	[(RubyDialogController *)dref stopIntervalTimer];
	[(RubyDialogController *)dref close];
}


void
RubyDialogCallback_close(RubyDialog *dref)
{
	[(RubyDialogController *)dref stopIntervalTimer];
	[(RubyDialogController *)dref close];
}

void
RubyDialogCallback_show(RubyDialog *dref)
{
	if (((RubyDialogController *)dref)->myTimer != NULL)
		[(RubyDialogController *)dref startIntervalTimer:-1];
	[[(RubyDialogController *)dref window] makeKeyAndOrderFront:nil];
}

void
RubyDialogCallback_hide(RubyDialog *dref)
{
	[(RubyDialogController *)dref stopIntervalTimer];
	[[(RubyDialogController *)dref window] orderOut:nil];	
}

int
RubyDialogCallback_isActive(RubyDialog *dref)
{
	return [[(RubyDialogController *)dref window] isVisible];
}

int
RubyDialogCallback_startIntervalTimer(RubyDialog *dref, float interval)
{
	return [(RubyDialogController *)dref startIntervalTimer:interval * 1000];
}

void
RubyDialogCallback_stopIntervalTimer(RubyDialog *dref)
{
	[(RubyDialogController *)dref stopIntervalTimer];
}

void
RubyDialogCallback_enableOnKeyHandler(RubyDialog *dref, int flag)
{
	((RubyDialogController *)dref)->onKeyHandlerEnabled = (flag != 0);
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

#if 0
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
#endif

RDSize
RubyDialogCallback_windowMinSize(RubyDialog *dref)
{
	return RDSizeFromNSSize([[(RubyDialogController *)dref window] minSize]);
}

void
RubyDialogCallback_setWindowMinSize(RubyDialog *dref, RDSize size)
{
	[[(RubyDialogController *)dref window] setMinSize:NSMakeSize(size.width, size.height)];
}

RDSize
RubyDialogCallback_windowSize(RubyDialog *dref)
{
	NSSize size = [[[(RubyDialogController *)dref window] contentView] bounds].size;
	RDSize rsize;
	rsize.width = size.width;
	rsize.height = size.height;
	return rsize;
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
}

void
RubyDialogCallback_setAutoResizeEnabled(RubyDialog *dref, int flag)
{
	((RubyDialogController *)dref)->autoResizeEnabled = (flag != 0);
//	NSWindow *win = [(RubyDialogController *)dref window];
//	[[win contentView] setAutoresizesSubviews:(flag != 0)];
}

int
RubyDialogCallback_isAutoResizeEnabled(RubyDialog *dref)
{
	return ((RubyDialogController *)dref)->autoResizeEnabled;
//	NSWindow *win = [(RubyDialogController *)dref window];
//	return [[win contentView] autoresizesSubviews];
}

void
RubyDialogCallback_createStandardButtons(RubyDialog *dref, const char *oktitle, const char *canceltitle)
{
	RubyDialogController *cont = (RubyDialogController *)dref;
	id okButton = [cont dialogItemAtIndex: 0];
	id cancelButton = [cont dialogItemAtIndex: 1];
	if (oktitle != NULL && oktitle[0] != 0) {
		[okButton setTitle: [NSString stringWithUTF8String: oktitle]];
		[[cont window] setDefaultButtonCell:[okButton cell]];
	} else [okButton setHidden: YES];
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
//	else if (strcmp(type, "button") == 0) {
//		offset.size.width = 24;
//		offset.size.height = 14;
//	}
	return offset;
}

RDItem *
RubyDialogCallback_createItem(RubyDialog *dref, const char *type, const char *title, RDRect frame)
{
	NSView *view = nil;
	NSView *itemView = nil;  //  The textview object is NSScrollView but the content is NSTextView
	NSRect rect, offset;
	RubyDialogController *cont = ((RubyDialogController *)dref);
	NSString *tstr = (title ? [NSString stringWithUTF8String: title] : nil);
	NSFont *font;
	font = [NSFont systemFontOfSize: [NSFont smallSystemFontSize]];
	
	rect = NSRectFromRDRect(frame);
	if (rect.size.width == 0.0f)
		rect.size.width = 1.0f;
	if (rect.size.height == 0.0f)
		rect.size.height = 1.0f;
	
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
		[tv setMinSize: NSMakeSize(0.0f, contentSize.height)];
		[tv setMaxSize: NSMakeSize(FLT_MAX, FLT_MAX)];
		[tv setVerticallyResizable: YES];
		[tv setHorizontallyResizable: NO];
		[tv setAutoresizingMask: NSViewWidthSizable];
		[[tv textContainer] setContainerSize: NSMakeSize(contentSize.width, FLT_MAX)];
		[[tv textContainer] setWidthTracksTextView: YES];
		[[tv textContainer] setHeightTracksTextView: NO];
		font = [NSFont userFixedPitchFontOfSize: 10.0f];
		[tv setFont: font];
		[tv setDelegate: cont];
		[tv setRichText: NO];
		[tv setSelectable: YES];
		[tv setEditable: YES];
		[sv setDocumentView: tv];
		view = sv;
		itemView = tv;
	} else if (strcmp(type, "view") == 0) {
		/*  Panel  */
		view = [[[NSView alloc] initWithFrame: rect] autorelease];
		/*  Autoresizing is handled in our own way  */
		[view setAutoresizesSubviews:NO];
		[view setAutoresizingMask:NSViewNotSizable];
	} else if (strcmp(type, "layout_view") == 0) {
		/*  Panel (for layout only)  */
		view = [[[NSView alloc] initWithFrame: rect] autorelease];
		/*  Autoresizing is handled in our own way  */
		[view setAutoresizesSubviews:NO];
		[view setAutoresizingMask:NSViewNotSizable];
	} else if (strcmp(type, "line") == 0) {
		/*  Separator line  */
		NSBox *box;
		if (rect.size.width > rect.size.height)
			rect.size.height = 1.0f;
		else rect.size.width = 1.0f;
		box = [[[NSBox alloc] initWithFrame: rect] autorelease];
		[box setBoxType:NSBoxSeparator];
		view = box;
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
	} else if (strcmp(type, "togglebutton") == 0) {
		/*  Toggle Button  */
		NSButton *bn = [[[NSButton alloc] initWithFrame: rect] autorelease];
		[bn setButtonType: NSToggleButton];
		[bn setBezelStyle: NSRegularSquareBezelStyle];
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
	} else if (strcmp(type, "table") == 0) {
		NSTableView *tv;
		NSScrollView *sv;
		NSSize contentSize;
		sv = [[[NSScrollView alloc] initWithFrame: rect] autorelease];
		[sv setHasVerticalScroller: YES];
		[sv setHasHorizontalScroller: YES];
		[sv setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
		[sv setBorderType: NSBezelBorder];
		[[sv verticalScroller] setControlSize: NSSmallControlSize];
		[[sv horizontalScroller] setControlSize: NSSmallControlSize];
		contentSize = [sv contentSize];		
		tv = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, contentSize.width, contentSize.height)] autorelease];
		[tv setDataSource:cont];
		[tv setDelegate:cont];
		[sv setDocumentView: tv];
		view = sv;
		itemView = tv;
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
	
	if (strcmp(type, "layout_view") == 0) {
		/*  Layout view: resize the window if it is too small  */
		NSRect contentFrame = [[[cont window] contentView] frame];
		NSRect crect = rect;
		id btn1, btn2;
		BOOL mod = NO;
		crect.size.width += crect.origin.x * 2;
		crect.size.height += crect.origin.y * 2;
		crect.origin.x = crect.origin.y = 0;
		btn1 = btn2 = nil;
		if (((btn1 = [cont dialogItemAtIndex:0]) != nil && ![btn1 isHidden]) ||
			((btn2 = [cont dialogItemAtIndex:1]) != nil && ![btn2 isHidden])) {
			//  At least one standard button is visible: we need to add area for the buttons
			NSRect r1, r2;
			r1 = (btn1 != nil ? [btn1 frame] : NSZeroRect);
			r2 = (btn2 != nil ? [btn2 frame] : NSZeroRect);
			r1 = NSUnionRect(r1, r2);
			crect.size.height += r1.size.height + r1.origin.y;
		}
		if (contentFrame.size.width < crect.size.width) {
			contentFrame.size.width = crect.size.width;
			mod = YES;
		}
		if (contentFrame.size.height < crect.size.height) {
			contentFrame.size.height = crect.size.height;
			mod = YES;
		}
		if (mod)
			[[cont window] setContentSize:contentFrame.size];
	}
	
	[cont addDialogItem: view];
	if (itemView == nil)
		itemView = view;

	if ([itemView respondsToSelector: @selector(setAction:)]) {
		[(id)itemView setAction: @selector(dialogItemAction:)];
		[(id)itemView setTarget: cont];
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
	if ([view isKindOfClass: [NSScrollView class]]) {
		[[(NSScrollView *)view documentView] setString: str];
	} else if ([view respondsToSelector: @selector(setStringValue:)]) {
		[(id)view setStringValue: str];
	}
}

void
RubyDialogCallback_getStringFromItem(RDItem *item, char *buf, int bufsize)
{
	NSView *view = (NSView *)item;
	NSString *str;
	if ([view isKindOfClass: [NSScrollView class]]) {
		str = [[(NSScrollView *)view documentView] string];
	} else if ([view respondsToSelector: @selector(stringValue)]) {
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
	if ([view isKindOfClass: [NSScrollView class]]) {
		str = [[(NSScrollView *)view documentView] string];
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
	if ([view isKindOfClass: [NSScrollView class]]) {
		[[(NSScrollView *)view documentView] setEditable: (flag != 0)];
	} else if ([view respondsToSelector: @selector(setEnabled:)]) {
		[(id)view setEnabled: (flag != 0)];
	}
}

int
RubyDialogCallback_isItemEnabled(RDItem *item)
{
	NSView *view = (NSView *)item;
	if ([view isKindOfClass: [NSScrollView class]]) {
		return [[(NSScrollView *)view documentView] isEditable];
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
RubyDialogCallback_setFontForItem(RDItem *item, int size, int family, int style, int weight)
{
	NSFont *font;
	NSFontDescriptor *desc;
	int mask = 0;
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]])
		itemView = [(NSScrollView *)itemView documentView];
	if (![itemView respondsToSelector:@selector(font)])
		return;
	font = [(id)itemView font];
	desc = [font fontDescriptor];
	if (size != 0)
		desc = [desc fontDescriptorWithSize:size];
	if (family == 2)
		desc = [desc fontDescriptorWithFamily:@"Times"];
	else if (family == 3)
		desc = [desc fontDescriptorWithFamily:@"Helvetica"];
	else if (family == 4)
		desc = [desc fontDescriptorWithFamily:@"Monaco"];
	if ((style == 2 || style == 3) && family != 4)
		mask |= NSItalicFontMask;
	if (weight == 2 && family != 4)
		mask |= NSBoldFontMask;
	if (mask != 0)
		desc = [desc fontDescriptorWithSymbolicTraits:mask];
	font = [NSFont fontWithDescriptor:desc size:0];  //  Setting size here does not work.
	[(id)itemView setFont:font];
}

int
RubyDialogCallback_getFontForItem(RDItem *item, int *size, int *family, int *style, int *weight)
{
	NSFont *font;
	NSFontDescriptor *desc;
	unsigned int symbolicTrait;
	int fam, sz, st, w;
	const unsigned int serifs = 
	NSFontOldStyleSerifsClass | NSFontTransitionalSerifsClass | NSFontModernSerifsClass |
	NSFontClarendonSerifsClass | NSFontSlabSerifsClass | NSFontFreeformSerifsClass;
	const unsigned int sans_serifs = NSFontSansSerifClass;
	const unsigned int monospace = NSFontMonoSpaceTrait;
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]])
		itemView = [(NSScrollView *)itemView documentView];
	
	if (![itemView respondsToSelector:@selector(font)])
		return 0;
	font = [(id)itemView font];
	desc = [font fontDescriptor];
	symbolicTrait = [desc symbolicTraits];
	
	fam = sz = st = w = 0;
	sz = [font pointSize];
	if (symbolicTrait & serifs)
		fam = 2;
	if (symbolicTrait & sans_serifs)
		fam = 3;
	if (symbolicTrait & monospace)
		fam = 4;
	if (symbolicTrait & NSFontItalicTrait)
		st = 3;
	if (symbolicTrait & NSFontBoldTrait)
		w = 2;
	if (family != NULL)
		*family = fam;
	if (style != NULL)
		*style = st;
	if (size != NULL)
		*size = sz;
	if (weight != NULL)
		*weight = w;
	return 1;
}

void
RubyDialogCallback_setForegroundColorForItem(RDItem *item, const double *col)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]])
		itemView = [(NSScrollView *)itemView documentView];
	if ([itemView respondsToSelector:@selector(setTextColor:)]) {
		NSColor *color = [NSColor colorWithDeviceRed:(CGFloat)col[0] green:(CGFloat)col[1] blue:(CGFloat)col[2] alpha:(CGFloat)col[3]];
		[(id)itemView setTextColor:color];
	}
}

void
RubyDialogCallback_setBackgroundColorForItem(RDItem *item, const double *col)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]])
		itemView = [(NSScrollView *)itemView documentView];
	if ([itemView respondsToSelector:@selector(setBackgroundColor:)]) {
		NSColor *color = [NSColor colorWithDeviceRed:(CGFloat)col[0] green:(CGFloat)col[1] blue:(CGFloat)col[2] alpha:(CGFloat)col[3]];
		[(id)itemView setBackgroundColor:color];
	}
}

void
RubyDialogCallback_getForegroundColorForItem(RDItem *item, double *col)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]])
		itemView = [(NSScrollView *)itemView documentView];
	if ([itemView respondsToSelector:@selector(textColor)]) {
		CGFloat rgba[4];
		NSColor *color = [(id)item textColor];
		[color getRed:rgba green:rgba + 1 blue:rgba + 2 alpha:rgba + 3];
		col[0] = rgba[0];
		col[1] = rgba[1];
		col[2] = rgba[2];
		col[3] = rgba[3];
	}
}

void
RubyDialogCallback_getBackgroundColorForItem(RDItem *item, double *col)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]])
		itemView = [(NSScrollView *)itemView documentView];
	if ([itemView respondsToSelector:@selector(backgroundColor)]) {
		CGFloat rgba[4];
		NSColor *color = [(id)item textColor];
		[color getRed:rgba green:rgba + 1 blue:rgba + 2 alpha:rgba + 3];
		col[0] = rgba[0];
		col[1] = rgba[1];
		col[2] = rgba[2];
		col[3] = rgba[3];
	}
}

int
RubyDialogCallback_appendString(RDItem *item, const char *str)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]])
		itemView = [(NSScrollView *)itemView documentView];
	if ([itemView respondsToSelector:@selector(textStorage)]) {
		NSTextStorage *st = [(id)itemView textStorage];
		[st replaceCharactersInRange:NSMakeRange([st length], 0) withString:[NSString stringWithUTF8String:str]];
		return 1;
	} else if ([itemView respondsToSelector:@selector(setStringValue:)]) {
		NSString *st = [(id)itemView stringValue];
		[(id)itemView setStringValue:[st stringByAppendingFormat:@"%s", str]];
		return 1;
	}
	return 0;
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

void
RubyDialogCallback_setNeedsDisplayInRect(RDItem *item, RDRect rect, int eraseBackground)
{
	NSRect nrect = NSMakeRect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
	[(NSView *)item setNeedsDisplayInRect:nrect];
}

int
RubyDialogCallback_countSubItems(RDItem *item)
{
	if ([(NSView *)item respondsToSelector: @selector(numberOfItems)]) {
		return (int)[(id)item numberOfItems];
	} else return 0;
}

int
RubyDialogCallback_appendSubItem(RDItem *item, const char *s)
{
	if ([(NSView *)item isKindOfClass: [NSPopUpButton class]]) {
		NSMenu *menu = [(NSPopUpButton *)item menu];
		id menuItem = [menu addItemWithTitle: [NSString stringWithUTF8String: s] action: nil keyEquivalent: @""];
		return (int)[menu indexOfItem: menuItem];
	} else return -1;
}

int
RubyDialogCallback_insertSubItem(RDItem *item, const char *s, int pos)
{
	if ([(NSView *)item isKindOfClass: [NSPopUpButton class]]) {
		NSMenu *menu = [(NSPopUpButton *)item menu];
		id menuItem = [menu insertItemWithTitle: [NSString stringWithUTF8String: s] action: nil keyEquivalent: @"" atIndex: pos];
		return (int)[menu indexOfItem: menuItem];
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
		return (int)[(NSPopUpButton *)item indexOfSelectedItem];
	}
	return -1;
}

RDSize
RubyDialogCallback_sizeOfString(RDItem *item, const char *s)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]])
		itemView = [(NSScrollView *)itemView documentView];
	if ([itemView respondsToSelector: @selector(font)]) {
		NSFont *font = [(id)itemView font];
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

char
RubyDialogCallback_deleteTableColumn(RDItem *item, int col)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]]) {
		itemView = [(NSScrollView *)itemView documentView];
		if ([itemView isKindOfClass:[NSTableView class]]) {
            id column = [(NSTableView *)itemView tableColumnWithIdentifier:[NSString stringWithFormat:@"%d", col]];
			if (column != nil) {
				[(NSTableView *)itemView removeTableColumn:column];
				return 1;
			}
		}
	}
	return 0;
}

char
RubyDialogCallback_insertTableColumn(RDItem *item, int col, const char *heading, int format, int width)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]]) {
		itemView = [(NSScrollView *)itemView documentView];
		if ([itemView isKindOfClass:[NSTableView class]]) {
			NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"%d", col]] autorelease];
			[[column headerCell] setStringValue:[NSString stringWithUTF8String:heading]];
			[(NSTableView *)itemView addTableColumn:column];
			return 1;
		}
	}
	return 0;
}

int
RubyDialogCallback_countTableColumn(RDItem *item)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]]) {
		itemView = [(NSScrollView *)itemView documentView];	
		if ([itemView isKindOfClass:[NSTableView class]]) {
			return (int)[(NSTableView *)itemView numberOfColumns];
		}
	}
	return -1;
}

char
RubyDialogCallback_isTableRowSelected(RDItem *item, int row)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]]) {
		itemView = [(NSScrollView *)itemView documentView];
		if ([itemView isKindOfClass:[NSTableView class]]) {
			return [(NSTableView *)itemView isRowSelected:row];
		}
	}
	return 0;
}

IntGroup *
RubyDialogCallback_selectedTableRows(RDItem *item)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]]) {
		itemView = [(NSScrollView *)itemView documentView];
		if ([itemView isKindOfClass:[NSTableView class]]) {
			NSIndexSet *iset = [(NSTableView *)itemView selectedRowIndexes];
			NSUInteger buf[20];
			int i, n;
			IntGroup *ig = IntGroupNew();
			NSRange range = NSMakeRange(0, 10000000);
			while ((n = (int)[iset getIndexes:buf maxCount:20 inIndexRange:&range]) > 0) {
				for (i = 0; i < n; i++)
					IntGroupAdd(ig, (int)buf[i], 1);
			}
			return ig;
		}
	}
	return NULL;
}

char
RubyDialogCallback_setSelectedTableRows(RDItem *item, struct IntGroup *rg, int extend)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]]) {
		itemView = [(NSScrollView *)itemView documentView];
		if ([itemView isKindOfClass:[NSTableView class]]) {
			NSMutableIndexSet *iset = [NSMutableIndexSet indexSet];
			int i, n;
			for (i = 0; (n = IntGroupGetNthPoint(rg, i)) >= 0; i++)
				[iset addIndex: i];
			[(NSTableView *)itemView selectRowIndexes:iset byExtendingSelection:extend];
			return 1;
		}
	}
	return 0;
}

void
RubyDialogCallback_refreshTable(RDItem *item)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]]) {
		itemView = [(NSScrollView *)itemView documentView];
		if ([itemView isKindOfClass:[NSTableView class]]) {
			[(NSTableView *)itemView reloadData];
		}
	}
}

int
RubyDialogCallback_lastKeyCode(void)
{
	NSEvent *currentEvent = [NSApp currentEvent];
	if ([currentEvent type] == NSKeyDown)
		return [[currentEvent characters] characterAtIndex:0];
	else return -1;
}

int
RubyDialogCallback_savePanel(const char *title, const char *dirname, const char *wildcard, char *buf, int bufsize)
{
	int result;
	NSSavePanel *panel = [NSSavePanel savePanel];
//	NSString *dirstr = (dirname != NULL ? [NSString stringWithUTF8String: dirname] : nil);
	[panel setTitle: [NSString stringWithUTF8String: title]];
    if (dirname != NULL)
        [panel setDirectoryURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:dirname]]];
    if (buf != NULL)
        [panel setNameFieldStringValue:[NSString stringWithUTF8String:buf]];
    result = (int)[panel runModal];
	if (result == NSFileHandlingPanelOKButton) {
		strncpy(buf, [[[panel URL] path] UTF8String], bufsize - 1);
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
//	NSString *dirstr = (dirname != NULL ? [NSString stringWithUTF8String: dirname] : nil);
	[panel setTitle: [NSString stringWithUTF8String: title]];
	if (for_directories) {
		[panel setCanChooseFiles: NO];
		[panel setCanChooseDirectories: YES];
	}
    if (dirname != NULL)
        [panel setDirectoryURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:dirname]]];
	result = (int)[panel runModal];
	if (result == NSOKButton) {
		NSArray *URLs = [panel URLs];
		int n = (int)[URLs count];
		int i;
		*array = (char **)malloc(sizeof(char *) * n);
		for (i = 0; i < n; i++) {
			(*array)[i] = strdup([[[URLs objectAtIndex: i] path] UTF8String]);
		}
		result = n;
	} else result = 0;
	[panel close];
	return result;
}

int
RubyDialogCallback_setSelectionInTextView(RDItem *item, int fromPos, int toPos)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]]) {
		itemView = [(NSScrollView *)itemView documentView];
	} else if ([itemView isKindOfClass:[NSTextField class]]) {
		itemView = [(id)itemView currentEditor];
	}
	if (itemView != nil && [itemView respondsToSelector:@selector(setSelectedRange:)]) {
		[(id)itemView setSelectedRange:NSMakeRange(fromPos, toPos - fromPos)];
		return 1;
	} else return 0;
}

int
RubyDialogCallback_getSelectionInTextView(RDItem *item, int *fromPos, int *toPos)
{
	NSView *itemView = (NSView *)item;
	if ([itemView isKindOfClass:[NSScrollView class]]) {
		itemView = [(NSScrollView *)itemView documentView];
	} else if ([itemView isKindOfClass:[NSTextField class]]) {
		itemView = [(id)itemView currentEditor];
	}
	if (itemView != nil && [itemView respondsToSelector:@selector(selectedRanges)]) {
		NSRange range = [[[(id)itemView selectedRanges] objectAtIndex:0] rangeValue];
		if (fromPos != NULL)
			*fromPos = (int)range.location;
		if (toPos != NULL)
            *toPos = (int)(range.location + range.length);
		return 1;
	} else {
		if (fromPos != NULL)
			*fromPos = -1;
		if (toPos != NULL)
			*toPos = -1;
		return 0;
	}
}

#pragma mark ====== Plain C Interface (Device Context) ======

RDDeviceContext *
RubyDialogCallback_getDeviceContextForRubyDialog(RubyDialog *dref)
{
	RubyDialogController *cont = (RubyDialogController *)dref;
	return (RDDeviceContext *)[[[cont window] graphicsContext] graphicsPort];
}

void
RubyDialogCallback_clear(RDDeviceContext *dc)
{
	CGContextRef cref = (CGContextRef)dc;
	CGRect rect = CGContextGetClipBoundingBox(cref);
	CGContextClearRect(cref, rect);
}

void
RubyDialogCallback_drawEllipse(RDDeviceContext *dc, float x, float y, float r1, float r2)
{
	CGContextRef cref = (CGContextRef)dc;
	CGRect rect = CGRectMake(x - r1, x - r2, r1 * 2, r2 * 2);
	CGContextStrokeEllipseInRect(cref, rect);
}

void
RubyDialogCallback_drawLine(RDDeviceContext *dc, int ncoords, float *coords)
{
	int i;
	CGContextRef cref = (CGContextRef)dc;
	CGContextBeginPath(cref);
	CGContextMoveToPoint(cref, coords[0], coords[1]);
	for (i = 1; i < ncoords; i++) {
		CGContextAddLineToPoint(cref, coords[i * 2], coords[i * 2 + 1]);
	}
	CGContextStrokePath(cref);
}

void
RubyDialogCallback_drawRectangle(RDDeviceContext *dc, float x, float y, float width, float height, float round)
{
	CGContextRef cref = (CGContextRef)dc;
	if (round * 2 > width)
		round = width * 0.5f;
	if (round * 2 > height)
		round = height * 0.5f;
	if (round < 1.0f)
		round = 0.0f;
	if (round > 0) {
		CGContextBeginPath(cref);
		CGContextAddArc(cref, x + round, y + round, round, 3.1415927f, 3.1415927f * 1.5f, 0);
		CGContextAddArc(cref, x + width - round, y + round, round, 3.1415927f * 1.5f, 3.1415927f * 2.0f, 0);
		CGContextAddArc(cref, x + width - round, y + height - round, round, 0, 3.1415927f * 0.5f, 0);
		CGContextAddArc(cref, x + round, y + height - round, round, 3.1415927f * 0.5f, 3.1415927f, 0);
		CGContextClosePath(cref);
		CGContextStrokePath(cref);
	} else {
		CGRect r = CGRectMake(x, y, width, height);
		CGContextStrokeRect(cref, r);
	}
}

void
RubyDialogCallback_drawText(RDDeviceContext *dc, const char *s, float x, float y)
{
	CGContextRef cref = (CGContextRef)dc;
	CGContextShowTextAtPoint(cref, x, y, s, strlen(s));
}

void
RubyDialogCallback_setFont(RDDeviceContext *dc, void **args)
{
	int i;
	float fontSize = 12;
	const char *fontName = NULL;
	CGContextRef cref = (CGContextRef)dc;
	for (i = 0; args[i] != NULL; i += 2) {
		if (strcmp((const char *)args[i], "size") == 0) {
			fontSize = *((float *)(args[i + 1]));
		} else if (strcmp((const char *)args[i], "style") == 0) {
		} else if (strcmp((const char *)args[i], "family") == 0) {
		} else if (strcmp((const char *)args[i], "weight") == 0) {
		} else if (strcmp((const char *)args[i], "name") == 0) {
			fontName = (const char *)args[i + 1];
		}
	}
	if (fontName == NULL)
		CGContextSetFontSize(cref, fontSize);
	else
		CGContextSelectFont(cref, fontName, fontSize, kCGEncodingFontSpecific);
}

void
RubyDialogCallback_setPen(RDDeviceContext *dc, void **args)
{
	int i;
	float width;
	CGContextRef cref = (CGContextRef)dc;
	width = 1.0f;
	if (args != NULL) {
		for (i = 0; args[i] != NULL; i += 2) {
			if (strcmp((const char *)args[i], "color") == 0) {
				float *fp = (float *)args[i + 1];
				CGContextSetRGBStrokeColor(cref, fp[0], fp[1], fp[2], fp[3]);
			} else if (strcmp((const char *)args[i], "width") == 0) {
				width = *((float *)(args[i + 1]));
				CGContextSetLineWidth(cref, width);
			} else if (strcmp((const char *)args[i], "style") == 0) {
				int style = (int)(args[i + 1]);
				CGFloat dash[4];
				CGFloat *dashp = dash;
				int dashLen;
				switch (style) {
					case 0: dashp = NULL; dashLen = 0; break;
					case 1: CGContextSetRGBStrokeColor(cref, 0, 0, 0, 0); break;
					case 2: dash[0] = dash[1] = width; dashLen = 2; break;
					case 3: dash[0] = width * 4; dash[1] = width * 2; dashLen = 2; break; 
					case 4: dash[0] = dash[1] = width * 2; dashLen = 2; break;
					case 5: dash[0] = dash[1] = width; dash[2] = dash[3] = width * 4; dashLen = 4; break;
					default: dashp = NULL; dashLen = 0; break;
				}
				if (style != 1)
					CGContextSetLineDash(cref, 0, dashp, dashLen);
			}
		}
	}
}

void
RubyDialogCallback_setBrush(RDDeviceContext *dc, void **args)
{
	int i;
	CGContextRef cref = (CGContextRef)dc;
	if (args != NULL) {
		for (i = 0; args[i] != NULL; i += 2) {
			if (strcmp((const char *)args[i], "color") == 0) {
				float *fp = (float *)args[i + 1];
				CGContextSetRGBFillColor(cref, fp[0], fp[1], fp[2], fp[3]);
			}
		}
	}
}

#pragma mark ====== Bitmap ======

RDBitmap *
RubyDialogCallback_createBitmap(int width, int height, int depth)
{
	CGContextRef bitmap;
	void *data = malloc(width * height * (depth / 8));
	CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
	bitmap = CGBitmapContextCreate(data, width, height, depth / 4, (depth / 8) * width, colorSpace, kCGImageAlphaLast);
	CGColorSpaceRelease(colorSpace);
	return (RDBitmap *)bitmap;
}

void
RubyDialogCallback_releaseBitmap(RDBitmap *bitmap)
{
	if (bitmap != NULL) {
		void *data = CGBitmapContextGetData((CGContextRef)bitmap);
		free(data);
		CGContextRelease((CGContextRef)bitmap);
	}
}


/*  Set focus on a bitmap and execute the given function  */
/*  This trick is necessary for platform like wxWidgets where the device context
    must be allocated on stack.
    It is not necessary for platform like Quartz-OSX where the device context is
    allocated in the heap.  */
static RDBitmap *s_temp_dc_pointer = NULL;
int
RubyDialogCallback_executeWithFocusOnBitmap(RDBitmap *bitmap, void (*callback)(void *), void *ptr)
{
	if (s_temp_dc_pointer != NULL)
		return -1;  /*  Recursive call is not allowed  */
	s_temp_dc_pointer = bitmap;
	(*callback)(ptr);
	s_temp_dc_pointer = NULL;
	return 0;
}

RDDeviceContext *
RubyDialogCallback_getDeviceContextForBitmap(RDBitmap *bitmap)
{
	return (RDDeviceContext *)bitmap;
}

int
RubyDialogCallback_saveBitmapToFile(RDBitmap *bitmap, const char *fname)
{
	CGImageRef outImage = CGBitmapContextCreateImage((CGContextRef)bitmap);
	CFURLRef outURL = (CFURLRef)[NSURL fileURLWithPath:[NSString stringWithUTF8String:fname]];
	int len = (int)strlen(fname);
	CFStringRef bitmapType = kUTTypePNG;
	int retval = 1;
	if (len >= 4) {
		if (strcasecmp(fname + len - 4, ".png") == 0)
			bitmapType = kUTTypePNG;
		else if (strcasecmp(fname + len - 4, ".tif") == 0 || (len >= 5 && strcasecmp(fname + len - 5, ".tiff") == 0))
			bitmapType = kUTTypeTIFF;
	}
    CGImageDestinationRef outDestination = CGImageDestinationCreateWithURL(outURL, kUTTypeJPEG, 1, NULL);
    CGImageDestinationAddImage(outDestination, outImage, NULL);
    if (!CGImageDestinationFinalize(outDestination))
		retval = 0;
    CFRelease(outDestination);
    CGImageRelease(outImage);
	return retval;
}
