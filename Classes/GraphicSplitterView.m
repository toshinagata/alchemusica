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

static NSMenuItem *
searchMenuItemWithTag(NSMenu *menu, int tag)
{
	int i;
	NSMenuItem *item;
	for (i = (int)[menu numberOfItems] - 1; i >= 0; i--) {
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
		rect.origin.x = 16.0f;
		rect.size.width = 100.0f;
		kindPopup = [[[MyPopUpButton allocWithZone: [self zone]] initWithFrame: rect] autorelease];
        [kindPopup setBezelStyle: NSShadowlessSquareBezelStyle];
        [kindPopup setBackgroundColor:[NSColor whiteColor]];
        [[kindPopup cell] setControlSize:NSMiniControlSize];
		rect.origin.x += rect.size.width + 16.0f;
		codePopup = [[[MyPopUpButton allocWithZone: [self zone]] initWithFrame: rect] autorelease];
        [codePopup setBezelStyle: NSShadowlessSquareBezelStyle];
        [codePopup setBackgroundColor:[NSColor whiteColor]];
        [[codePopup cell] setControlSize:NSMiniControlSize];
        rect.origin.x += rect.size.width + 16.0f;
        rect.size.width = 40.0f;
        rect.origin.y -= 2;
        trackLabelText = [[[NSTextField allocWithZone:[self zone]] initWithFrame:rect] autorelease];
        rect.origin.y += 2;
        rect.origin.x += rect.size.width + 4.0f;
        rect.size.width = 100.0f;
        trackPopup = [[[MyPopUpButton allocWithZone:[self zone]] initWithFrame:rect] autorelease];
        [trackPopup setBezelStyle: NSShadowlessSquareBezelStyle];
        [trackPopup setBackgroundColor:[NSColor whiteColor]];
        [[trackPopup cell] setControlSize:NSMiniControlSize];
		font = [NSFont systemFontOfSize: [NSFont smallSystemFontSize]];
		[kindPopup setFont: font];
		[codePopup setFont: font];
        [trackLabelText setBezeled:NO];
        [trackLabelText setSelectable:NO];
        [trackLabelText setDrawsBackground:NO];
        [trackPopup setFont: font];
		[self addSubview: kindPopup];
		[self addSubview: codePopup];
        [self addSubview: trackLabelText];
        [self addSubview: trackPopup];
		for (i = 0; i < sizeof(sKindMenuItems) / sizeof(sKindMenuItems[0]); i++) {
			[kindPopup addItemWithTitle: sKindMenuItems[i].title];
			[[kindPopup itemAtIndex: i] setTag: sKindMenuItems[i].kind];
		}
		[kindPopup selectItemAtIndex: [kindPopup indexOfItemWithTag: kMDEventNote]];
		[kindPopup setEnabled: YES];
		[codePopup setEnabled: NO];
        [trackPopup setEnabled: YES];
		font = [NSFont systemFontOfSize: [NSFont smallSystemFontSize] - 2];
        [trackLabelText setFont: font];
        [trackLabelText setStringValue:@"Track:"];
    }
    return self;
}

static NSMenu *
trackPopUp(int count)
{
    NSMenu *menu;
    int i;
    menu = [[[NSMenu alloc] initWithTitle: @"tracks"] autorelease];
    for (i = 0; i <= count; i++) {
        NSString *s;
        if (i == 0)
            s = @"(As Piano Roll)";
        else if (i == 1)
            s = @"C";
        else s = [NSString stringWithFormat:@"%d", i - 1];
        [menu addItemWithTitle:s action:nil keyEquivalent:@""];
    }
    return menu;
}

//  Initialize target-action relationship
- (void)viewDidMoveToSuperview
{
	id target = [[[self superview] window] windowController];
	[kindPopup setTarget: target];
	[kindPopup setAction: @selector(kindPopUpPressed:)];
	if (sControlSubmenu == nil) {
		sControlSubmenu = [MDMenuWithControlNames(nil, nil, 0) retain];
	}
    [codePopup setTarget: target];
    [codePopup setAction: @selector(codeMenuItemSelected:)];
    [trackPopup setTarget:target];
    [trackPopup setAction:@selector(trackPopUpPressedInSplitterView:)];
    [trackPopup setMenu:trackPopUp([target trackCount])];
}

- (void)drawRect:(NSRect)rect {
	NSRect bounds = [self bounds];
	NSPoint pt1, pt2;
	NSDrawWindowBackground(bounds);
	[[NSColor lightGrayColor] set];
	pt1.x = bounds.origin.x;
	pt2.x = bounds.origin.x + bounds.size.width;
	pt1.y = pt2.y = bounds.origin.y + 0.5f;
	[NSBezierPath strokeLineFromPoint: pt1 toPoint: pt2];
	pt1.y = pt2.y = bounds.origin.y + bounds.size.height - 0.5f;
	[NSBezierPath strokeLineFromPoint: pt1 toPoint: pt2];
}

- (void)mouseDown: (NSEvent *)theEvent
{
	NSPoint mousePt, startPt, origin;
	NSEventType type;
	GraphicWindowController *controller = (GraphicWindowController *)[[self window] windowController];
    GraphicBackgroundView *container = [controller enclosingContainerForClientView:self];
	startPt = [theEvent locationInWindow];
    if (container != nil)
        origin = [container frame].origin;
	else origin = [self frame].origin;
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
    NSPoint pt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    if ((NSPointInRect(pt, [kindPopup frame]) && [kindPopup isEnabled])
        || (NSPointInRect(pt, [trackPopup frame]) && [trackPopup isEnabled])
        || (NSPointInRect(pt, [codePopup frame]) && [codePopup isEnabled]))
        [[NSCursor arrowCursor] set];
    else
        [[NSCursor verticalMoveCursor] set];
}

- (void)createSubmenus
{
}

- (void)setKindAndCode: (int32_t)kindAndCode
{
	int kind, code;
	NSMenuItem *item;
	code = (kindAndCode & 65535);
	kind = ((kindAndCode >> 16) & 65535);
	if (kind != 65535) {
		item = searchMenuItemWithTag([kindPopup menu], kind);
		if (item != nil) {
			[kindPopup selectItem: item];
			if (kind == kMDEventControl) {
				[codePopup setMenu: sControlSubmenu];
				[codePopup setEnabled: YES];
			} else {
				[codePopup setMenu: [[[NSMenu allocWithZone: [self zone]] initWithTitle: @""] autorelease]];
				[codePopup setEnabled: NO];
			}
		}
	}
	if (code != 65535) {
		item = searchMenuItemWithTag([codePopup menu], code);
		if (item != nil) {
			[codePopup selectItem: item];
		}
	}
}

- (void)setTrack:(int)track
{
    [trackPopup selectItemAtIndex:track + 1];
}

- (void)rebuildTrackPopup
{
    int i, count;
    id target = [trackPopup target];
    i = [trackPopup indexOfSelectedItem];
    count = [target trackCount];
    [trackPopup setMenu:trackPopUp(count)];
    
}

@end
