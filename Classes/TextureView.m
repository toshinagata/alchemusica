//
//  TextureView.m
//  Alchemusica
//
/*
    Copyright (c) 2008-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "TextureView.h"

@implementation TextureView

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (BOOL)becomeFirstResponder
{
	[self setNeedsDisplay: YES];
    [self setKeyboardFocusRingNeedsDisplayInRect: [self bounds]];
	return YES;
}
	
- (BOOL)resignFirstResponder
{
	[self setNeedsDisplay: YES];
    [self setKeyboardFocusRingNeedsDisplayInRect: [self bounds]];
	return YES;
}
	
- (id)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect]) != nil) {
		// Add initialization code here
	}
	return self;
}

- (void)drawRect:(NSRect)rect
{
	static NSRectEdge mySides[] = {NSMinYEdge, NSMaxXEdge, NSMaxYEdge, NSMinXEdge, NSMinYEdge, NSMaxXEdge};
	static NSColor *myColors[] = {NULL, NULL, NULL, NULL, NULL, NULL};
	NSRect aRect = [self bounds];
	if (myColors[0] == NULL) {
		static float myFloatColors[] = {0.5f, 0.5f, 0.92f, 0.92f, 0.85f, 0.85f};
		int i;
		for (i = 0; i < sizeof(myFloatColors) / sizeof(myFloatColors[0]); i++) {
			float f = myFloatColors[i];
			myColors[i] = [[NSColor colorWithDeviceWhite: f alpha: 1.0f] retain];
		}
	}
	aRect = NSDrawColorTiledRects(aRect, rect, mySides, myColors, 6);
	[[NSColor colorWithDeviceWhite: 0.8f alpha: 1.0f] set];
	NSRectFill(aRect);

	if ([[self window] firstResponder] == self) {
		NSSetFocusRingStyle(NSFocusRingOnly);
		NSRectFill([self bounds]);
	}
}

@end
