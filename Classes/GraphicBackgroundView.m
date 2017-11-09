//
//  GraphicBackgroundView.m
//  Alchemusica
//
//  Created by Toshi Nagata on 06/11/14.
//  Copyright 2006-2011 Toshi Nagata. All rights reserved.
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

#import "GraphicBackgroundView.h"
#import "GraphicWindowController.h"
#import "GraphicClientView.h"

@implementation GraphicBackgroundView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

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
	
- (void)drawRect:(NSRect)rect {
	NSRect bounds;
	[super drawRect: rect];
	bounds = [self bounds];
	if ([[self window] isMainWindow] && [[self window] firstResponder] == self) {
		NSSetFocusRingStyle(NSFocusRingOnly);
		NSRectFill(bounds);
	}
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize
{
	/*  Call the window controller's "backgroundView:resizedWithOldSize:"  */
	id cont = [[self window] windowController];
    if ([cont respondsToSelector: @selector(backgroundView:resizedWithOldSize:)]) {
        if (![cont backgroundView:self resizedWithOldSize:oldBoundsSize])
            [super resizeSubviewsWithOldSize:oldBoundsSize];
	}
}

- (void)flagsChanged:(NSEvent *)theEvent
{
	id clientView = [[[self window] windowController] lastMouseClientView];
	if (clientView != nil)
		[clientView doFlagsChanged:theEvent];
	else [super flagsChanged:theEvent];
}

@end
