//
//  MyPopUpButton.m
//  Alchemusica
//
//  Created by Toshi Nagata on Sun Jan 1 2006.
/*
    Copyright (c) 2006-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "MyPopUpButton.h"

@implementation MyPopUpButton

static NSImage *sTriangleImage;

+ (NSImage *)triangleImage
{
	if (sTriangleImage == nil) {
		sTriangleImage = [[NSImage allocWithZone: [self zone]] initWithContentsOfFile: [[NSBundle mainBundle] pathForResource: @"triangle.png" ofType: nil]];
	}
	return sTriangleImage;
}

- (void)drawRect: (NSRect)aRect
{
    NSRect theRect, r;
	NSPoint center;
	NSSize size;
	NSImage *theImage;
	float fraction;
	id item = [self selectedItem];
	theImage = [item image];
	if (theImage != nil)
		[[theImage retain] autorelease];
	[item setImage: nil];
	[super drawRect: aRect];
	[item setImage: theImage];
	theRect = [self bounds];
	center.x = theRect.origin.x + theRect.size.width / 2;
	center.y = theRect.origin.y + theRect.size.height / 2;
	if ([self isEnabled])
		fraction = 1.0;
	else fraction = 0.5;
	if (theImage != nil) {
		size = [theImage size];
        r.origin.x = center.x - size.width / 2;
        r.origin.y = center.y - size.height / 2;
        r.size = size;
        [theImage drawInRect:r fromRect:NSZeroRect operation:NSCompositeSourceAtop fraction:fraction respectFlipped:YES hints:nil];
	}
//	theRect = NSMakeRect(theRect.origin.x + theRect.size.width - 7, theRect.origin.y + theRect.size.height - 7, 5, 5);
    r.origin.x = theRect.origin.x + theRect.size.width - 7;
    r.origin.y = theRect.origin.y + theRect.size.height - 7;
    r.size.width = 5;
    r.size.height = 5;
    [[MyPopUpButton triangleImage] drawInRect:r fromRect:NSZeroRect operation:NSCompositeSourceAtop fraction:fraction respectFlipped:YES hints:nil];
}


@end
