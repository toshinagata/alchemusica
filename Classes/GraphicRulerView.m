//
//  GraphicRulerView.m
//
/*
    Copyright (c) 2000-2017 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "GraphicRulerView.h"
#import "GraphicClientView.h"
#import "NSCursorAdditions.h"
#import "MyDocument.h"
#import "MyAppController.h"  //  for getOSXVersion

static NSFont *sRulerLabelFont;

@implementation GraphicRulerView

+ (NSFont *)rulerLabelFont
{
	if (sRulerLabelFont == nil)
		sRulerLabelFont = [[NSFont userFontOfSize: 0] retain];
	return sRulerLabelFont;
}

+ (void)setRulerLabelFont: (NSFont *)aFont
{
	[sRulerLabelFont release];
	sRulerLabelFont = [aFont retain];
}

- (int)rulerViewType
{
	if (clientView != nil)
		return [(GraphicClientView *)clientView clientViewType];
	else return kGraphicGenericViewType;
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
		dragStartPoint = NSMakePoint(-10000, -10000);
    }
    return self;
}

- (void)dealloc
{
	[self releaseClientView];
	[super dealloc];
}

- (NSRect)loupeRect
{
	if (dragStartPoint.x > -10000) {
		NSRect rect = [self bounds];
		if (dragStartPoint.y > dragEndPoint.y) {
			rect.origin.y = dragEndPoint.y;
			rect.size.height = dragStartPoint.y - dragEndPoint.y;
		} else {
			rect.origin.y = dragStartPoint.y;
			rect.size.height = dragEndPoint.y - dragStartPoint.y;
		}
		return rect;
	} else return NSZeroRect;
}

- (void)drawRect:(NSRect)rect
{
	float x, y;
	NSRect lrect = [self loupeRect];
	if (lrect.size.width > 0) {
		[[[MyDocument colorForSelectingRange] colorWithAlphaComponent: 0.1f] set];
		[NSBezierPath fillRect:lrect];
		x = lrect.origin.x;
		y = lrect.origin.y;
		[[NSColor blackColor] set];
		[NSBezierPath strokeLineFromPoint: NSMakePoint(x, y) toPoint:NSMakePoint(x + lrect.size.width, y)];
		y += lrect.size.height;
		[NSBezierPath strokeLineFromPoint: NSMakePoint(x, y) toPoint:NSMakePoint(x + lrect.size.width, y)];
	}
}

- (void)releaseClientView
{
	if (clientView != nil) {
		[[NSNotificationCenter defaultCenter]
			removeObserver: self name: nil object: clientView];
		[[NSNotificationCenter defaultCenter]
			removeObserver: self name: nil object: [clientView superview]];
		[clientView release];
		clientView = nil;
	}
}

//  Respond when the scroll position of the client view changed
- (void)superBoundsDidChange: (NSNotification *)aNotification
{
	NSView *view = (NSView *)[aNotification object];
	if (view == [clientView superview]) {
		NSRect rect = [view bounds];
		NSRect newRect = [[self superview] bounds];
		newRect.origin.y = rect.origin.y;
		[self scrollPoint: newRect.origin];
	}
}

//  Respond when the frame of the superview of the client view changed
//  i.e. the scroll view containing the client view is resized
- (void)superFrameDidChange: (NSNotification *)aNotification
{
	NSView *view = (NSView *)[aNotification object];
	if (view == [clientView superview]) {
		NSRect rect = [view frame];
		NSRect newRect = [[self superview] frame];
		rect = [[[self superview] superview] convertRect: rect fromView: [view superview]];
		newRect.origin.y = rect.origin.y;
		newRect.size.height = rect.size.height;
		[[self superview] setFrame: newRect];
	}
}

//  Respond when the frame of the client view, i.e. data range and/or scale are changed
- (void)frameDidChange: (NSNotification *)aNotification
{
	NSView *view = (NSView *)[aNotification object];
	if (view == clientView) {
		NSRect rect = [view frame];
		NSRect newRect = [self frame];
		newRect.size.height = rect.size.height;
		[self setFrame: newRect];
        [self setNeedsDisplay:YES];
	}
}

- (void)setClientView: (NSView *)aView
{
	[self releaseClientView];
	[[NSNotificationCenter defaultCenter]
		addObserver: self
		selector: @selector(superBoundsDidChange:)
		name: NSViewBoundsDidChangeNotification
		object: [aView superview]];
	[[NSNotificationCenter defaultCenter]
		addObserver: self
		selector: @selector(superFrameDidChange:)
		name: NSViewFrameDidChangeNotification
		object: [aView superview]];
	[[NSNotificationCenter defaultCenter]
		addObserver: self
		selector: @selector(frameDidChange:)
		name: NSViewFrameDidChangeNotification
		object: aView];
	clientView = [aView retain];
}

- (NSView *)clientView
{
	return clientView;
}


- (void)invalidateLoupeRect
{
	NSRect lrect = [self loupeRect];
	lrect = NSInsetRect(lrect, -1, -1);
	[self setNeedsDisplayInRect:lrect];
}

- (void)mouseUp: (NSEvent *)theEvent
{
	GraphicClientView *cv = (GraphicClientView *)clientView;
	if ([theEvent clickCount] == 2 && ([theEvent modifierFlags] & NSAlternateKeyMask) != 0) {
		[cv setVisibleRangeMin:0.0f max:1.0f];
	} else if (dragStartPoint.x != -10000) {
		float y1, y2, miny, maxy;
		int32_t tick;  //  Dummy
		[self invalidateLoupeRect];
		[cv convertFromPoint:dragStartPoint toY:&y1 andTick:&tick];
		[cv convertFromPoint:[cv convertPoint:[theEvent locationInWindow] fromView:nil] toY:&y2 andTick:&tick];
		if (y1 > y2) {
			float yw = y1;
			y1 = y2;
			y2 = yw;
		}
		miny = [cv minValue];
		maxy = [cv maxValue];
		if (y2 - y1 < 2.0f) {
			if (y1 > maxy - 2.0f) {
				y2 = maxy;
				y1 = maxy - 2.0f;
			} else {
				y2 = y1 + 2.0f;
			}
		}
		y1 = (y1 - miny) / (maxy - miny);
		y2 = (y2 - miny) / (maxy - miny);
		[cv setVisibleRangeMin:y1 max:y2];
	}
	dragStartPoint = NSMakePoint(-10000, -10000);
}

- (void)mouseDragged: (NSEvent *)theEvent
{
    NSPoint pt;
//    NSRect bounds;
//    NSValue *val;
	pt = [self convertPoint: [theEvent locationInWindow] fromView: nil];
	if (dragStartPoint.x == -10000) {
		if ([theEvent modifierFlags] & NSAlternateKeyMask) {
			/*  Start option-dragging  */
			dragStartPoint = pt;
		}
		return;
	} else {
		[self invalidateLoupeRect];
		dragEndPoint = pt;
		[self invalidateLoupeRect];
	}
	[self displayIfNeeded];
}

- (void)doMouseMoved: (NSEvent *)theEvent
{
    if ([theEvent modifierFlags] & NSAlternateKeyMask)
        [[NSCursor loupeCursor] set];
    else [[NSCursor arrowCursor] set];
}

- (void)scrollWheel:(NSEvent *)theEvent
{
	float dy, newpos;
	static int scroll_direction = 0;
	
	if (scroll_direction == 0) {
		//  Scroll wheel behavior was changed in 10.7
		if ([(MyAppController *)[NSApp delegate] getOSXVersion] < 10700)
			scroll_direction = -1;
		else scroll_direction = 1;
	}
	dy = [theEvent deltaY];
	if (dy != 0.0) {
		//  Implement vertical scroll by ourselves
		GraphicClientView *cview = (GraphicClientView *)[self clientView];
		newpos = [cview scrollVerticalPosition] + dy * (4 * scroll_direction);
		[cview scrollToVerticalPosition:newpos];
	}
}

@end
