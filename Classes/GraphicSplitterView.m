//
//  GraphicSplitterView.m
//  Created by Toshi Nagata on Sun Feb 09 2003.
//
/*
    Copyright (c) 2003-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "GraphicSplitterView.h"
#import "GraphicWindowController.h"
#import "NSCursorAdditions.h"
#import "MDObjects.h"

@implementation GraphicSplitterView

static NSMenu *sControlSubmenu;
// static NSMenu *sKeyPresSubmenu;

static struct sKindMenuItems {
	int kind;
	NSString *title;
} sKindMenuItems[] = {
 	{ kMDEventNote, @"Note Velocity" },
	{ kMDEventInternalNoteOff, @"Release Velocity" },
	{ kMDEventControl, @"Control" },
	{ kMDEventPitchBend, @"Pitch Bend" },
	{ kMDEventChanPres, @"Channel Pressure" },
	{ kMDEventKeyPres, @"Key Pressure" },
	{ kMDEventTempo, @"Tempo" }
};

/*
static unsigned char sControlSubmenuCodes[] = { 1, 7, 10, 11, 64, 71, 72, 73, 74 };

static void
addControlNameToMenu(int code, NSMenu *menu, id target)
{
	MDEvent event;
	char name[64];
	NSMenuItem *item;
	MDEventInit(&event);
	MDSetKind(&event, kMDEventControl);
	MDSetCode(&event, (code & 0x7f));
	MDEventToKindString(&event, name, sizeof name);
	[menu addItemWithTitle: [NSString stringWithCString: name + 1]  //  Chop the "*" at the top
		action: @selector(codeMenuItemSelected:) keyEquivalent: @""];
	item = (NSMenuItem *)[menu itemAtIndex: [menu numberOfItems] - 1];
	[item setTag: (code & 0x7f)];
	[item setTarget: target];
}
*/

static NSMenuItem *
searchMenuItemWithTag(NSMenu *menu, int tag)
{
	int i;
	NSMenuItem *item;
	for (i = [menu numberOfItems] - 1; i >= 0; i--) {
		item = (NSMenuItem *)[menu itemAtIndex: i];
		if ([item tag] == tag)
			return item;
		if ([item hasSubmenu]) {
			item = searchMenuItemWithTag([item submenu], tag);
			if (item != nil)
				return item;
		}
	}
	return nil;		
}

- (id)initWithFrame:(NSRect)frame {
	int i;
	NSFont *font;
    self = [super initWithFrame: frame];
    if (self && frame.size.height >= 10.0) {
		NSRect rect = [self bounds];
		rect.origin.y++;
		rect.size.height--;
		rect.origin.x = 16.0;
		rect.size.width = 100.0;
		kindPopup = [[[NSPopUpButton allocWithZone: [self zone]] initWithFrame: rect] autorelease];
		kindText = [[[NSTextField allocWithZone: [self zone]] initWithFrame: rect] autorelease];
		rect.origin.x += rect.size.width + 16.0;
		codePopup = [[[NSPopUpButton allocWithZone: [self zone]] initWithFrame: rect] autorelease];
		codeText = [[[NSTextField allocWithZone: [self zone]] initWithFrame: rect] autorelease];
		font = [NSFont systemFontOfSize: [NSFont smallSystemFontSize]];
		[kindPopup setFont: font];
		[kindText setBezeled: YES];
		[kindText setSelectable: NO];
		[codePopup setFont: font];
		[codeText setBezeled: YES];
		[codeText setSelectable: NO];
		[self addSubview: kindText];
		[self addSubview: kindPopup];
		[self addSubview: codeText];
		[self addSubview: codePopup];
		for (i = 0; i < sizeof(sKindMenuItems) / sizeof(sKindMenuItems[0]); i++) {
			[kindPopup addItemWithTitle: sKindMenuItems[i].title];
			[[kindPopup itemAtIndex: i] setTag: sKindMenuItems[i].kind];
		}
		[kindPopup selectItemAtIndex: [kindPopup indexOfItemWithTag: kMDEventNote]];
		[kindText setStringValue: [kindPopup titleOfSelectedItem]];
		[kindPopup setEnabled: YES];
		[codePopup setEnabled: NO];
		[kindPopup setTransparent: YES];
		[codePopup setTransparent: YES];
		font = [NSFont systemFontOfSize: [NSFont smallSystemFontSize] - 2];
		[codeText setFont: font];
		[kindText setFont: font];
    }
    return self;
}

//  Initialize target-action relationship
- (void)viewDidMoveToSuperview
{
	id target = [[self window] windowController];
	[kindPopup setTarget: target];
	[kindPopup setAction: @selector(kindPopUpPressed:)];
	if (sControlSubmenu == nil) {
		sControlSubmenu = [MDMenuWithControlNames(target, @selector(codeMenuItemSelected:), 0) retain];
	/*	NSMenu *submenu;
		sControlSubmenu = [[NSMenu allocWithZone: [self zone]] initWithTitle: @"Control names"];
		for (i = 0; i < sizeof(sControlSubmenuCodes) / sizeof(sControlSubmenuCodes[0]); i++)
			addControlNameToMenu(sControlSubmenuCodes[i], sControlSubmenu, target);
		for (i = 0; i < 127; i++) {
			if (i % 32 == 0) {
				[sControlSubmenu addItemWithTitle: [NSString stringWithFormat: @"%d-%d", i, i + 31]
					action: nil keyEquivalent: @""];
				submenu = [[[NSMenu allocWithZone: [self zone]] initWithTitle: @""] autorelease];
				[[sControlSubmenu itemAtIndex: [sControlSubmenu numberOfItems] - 1]
					setSubmenu: submenu];
			}
			for (j = sizeof(sControlSubmenuCodes) / sizeof(sControlSubmenuCodes[0]) - 1; j >= 0; j--) {
				if (i == sControlSubmenuCodes[j])
					break;
			}
			if (j < 0)
				addControlNameToMenu(i, submenu, target);
		} */
	}
}

- (void)drawRect:(NSRect)rect {
	NSRect bounds = [self bounds];
	NSPoint pt1, pt2;
	NSDrawWindowBackground(bounds);
//	NSEraseRect(bounds);
	[[NSColor lightGrayColor] set];
	pt1.x = bounds.origin.x;
	pt2.x = bounds.origin.x + bounds.size.width;
	pt1.y = pt2.y = bounds.origin.y + 0.5;
	[NSBezierPath strokeLineFromPoint: pt1 toPoint: pt2];
	pt1.y = pt2.y = bounds.origin.y + bounds.size.height - 0.5;
	[NSBezierPath strokeLineFromPoint: pt1 toPoint: pt2];
}

- (void)mouseDown: (NSEvent *)theEvent
{
	NSPoint mousePt, startPt, origin;
	NSEventType type;
	GraphicWindowController *controller = (GraphicWindowController *)[[self window] windowController];
	startPt = [theEvent locationInWindow];
	origin = [self frame].origin;
	[controller splitterViewStartedDragging:self];
	do {
		theEvent = [[self window] nextEventMatchingMask: NSLeftMouseUpMask | NSLeftMouseDraggedMask];
		mousePt = [theEvent locationInWindow];
		type = [theEvent type];
		if (type != NSLeftMouseUp && type != NSLeftMouseDragged)
			continue;
		[controller splitterView: self isDraggedTo: origin.y + (mousePt.y - startPt.y) confirm: (type == NSLeftMouseUp)];
	} while (type == NSLeftMouseDragged);
}

- (void)doMouseMoved:(NSEvent *)theEvent
{
	[[NSCursor verticalMoveCursor] set];
}

- (void)createSubmenus
{
}

- (void)setKindAndCode: (long)kindAndCode
{
	int kind, code;
	NSMenuItem *item;
	code = (kindAndCode & 65535);
	kind = ((kindAndCode >> 16) & 65535);
	if (kind != 65535) {
		item = searchMenuItemWithTag([kindPopup menu], kind);
		if (item != nil) {
			[kindPopup selectItem: nil];
			[kindText setStringValue: [item title]];
			if (kind == kMDEventControl) {
				[codePopup setMenu: sControlSubmenu];
				[codePopup setEnabled: YES];
			} else {
				[codePopup setMenu: [[[NSMenu allocWithZone: [self zone]] initWithTitle: @""] autorelease]];
				[codePopup setEnabled: NO];
				[codeText setStringValue: @""];
			}
		}
	}
	if (code != 65535) {
		item = searchMenuItemWithTag([codePopup menu], code);
		if (item != nil) {
			[codePopup selectItem: item];
			[codeText setStringValue: [item title]];
		}
	}
}

@end
