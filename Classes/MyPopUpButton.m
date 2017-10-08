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
	NSSize size;
	NSImage *theImage;
    NSString *theTitle;
	id item = [self selectedItem];
    theImage = [item image];
    theTitle = [item title];
    theRect = [self bounds];
    if (theImage != nil) {
        //  Draw only background
        NSPoint center;
        float fraction;
        [[theImage retain] autorelease];
        if (theTitle != nil)
            [[theTitle retain] autorelease];
        [item setImage:nil];
        [item setTitle:@""];
        [super drawRect:aRect];
        [item setTitle:theTitle];
        [item setImage:theImage];
        //  And draw the image as we like
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
    } else {
        //  Draw the content as usual
        NSAttributedString *atitle;
        if (theTitle != nil && textColor != nil) {
            //  Set color
            NSFont *font;
            NSDictionary *attr;
            font = [NSFont labelFontOfSize:[NSFont systemFontSizeForControlSize:[self controlSize]]];
            attr = [NSDictionary dictionaryWithObjectsAndKeys:
                    textColor, NSForegroundColorAttributeName,
                    font, NSFontAttributeName,
                    nil];
            [theTitle retain];
            atitle = [[NSAttributedString alloc] initWithString:theTitle attributes: attr];
            [item setAttributedTitle:atitle];
            [super drawRect:aRect];
            [item setTitle:theTitle];
            [theTitle release];
        } else {
            [super drawRect:aRect];
        }
    }
    r.origin.x = theRect.origin.x + theRect.size.width - 7;
    r.origin.y = theRect.origin.y + theRect.size.height - 7;
    r.size.width = 5;
    r.size.height = 5;
    [[MyPopUpButton triangleImage] drawInRect:r fromRect:NSZeroRect operation:NSCompositeSourceAtop fraction:fraction respectFlipped:YES hints:nil];
}

- (void)setTextColor:(NSColor *)color
{
    [color retain];
    [textColor release];
    textColor = color;
}

- (NSColor *)textColor
{
    return textColor;
}

@end
