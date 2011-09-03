//
//  GraphicRulerView.m
//
/*
    Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "GraphicRulerView.h"

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
    }
    return self;
}

- (void)dealloc
{
	[self releaseClientView];
	[super dealloc];
}

- (void)drawRect:(NSRect)rect {
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

@end
