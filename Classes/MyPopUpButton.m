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

static NSImage *sTriangleImage, *sDoubleTriangleImage;

+ (NSImage *)triangleImage
{
	if (sTriangleImage == nil) {
		sTriangleImage = [[NSImage allocWithZone: [self zone]] initWithContentsOfFile: [[NSBundle mainBundle] pathForResource: @"triangle.png" ofType: nil]];
	}
	return sTriangleImage;
}

+ (NSImage *)doubleTriangleImage
{
    if (sDoubleTriangleImage == nil) {
        sDoubleTriangleImage = [[NSImage allocWithZone: [self zone]] initWithContentsOfFile: [[NSBundle mainBundle] pathForResource: @"double_triangle.png" ofType: nil]];
    }
    return sDoubleTriangleImage;
}

- (void)dealloc
{
    if (textColor != nil)
        [textColor release];
    if (backgroundColor != nil)
        [backgroundColor release];
    [super dealloc];
}

- (void)superDrawRect: (NSRect)aRect
{
    if (backgroundColor != nil) {
        [[NSColor lightGrayColor] set];
        NSFrameRect(aRect);
        [backgroundColor set];
        NSRectFill(NSInsetRect(aRect, 1, 1));
    } else [super drawRect:aRect];
}

- (void)drawRect: (NSRect)aRect
{
    NSRect theRect, r;
	NSSize size;
    float fraction;
	NSImage *theImage;
    NSString *theTitle;
	id item = [self selectedItem];
    theImage = [item image];
    theTitle = [item title];
    theRect = [self bounds];
    if ([self isEnabled])
        fraction = 1.0f;
    else fraction = 0.5f;
    if (theTitle != nil)
        [[theTitle retain] autorelease];
    [item setTitle:@""];
    if (theImage != nil) {
        //  Draw only background
        NSPoint center;
        [[theImage retain] autorelease];
        [item setImage:nil];
        [self superDrawRect:aRect];
        [item setImage:theImage];
        //  And draw the image as we like
        center.x = theRect.origin.x + theRect.size.width / 2;
        center.y = theRect.origin.y + theRect.size.height / 2;
        if (theImage != nil) {
            size = [theImage size];
            r.origin.x = center.x - size.width / 2;
            r.origin.y = center.y - size.height / 2;
            r.size = size;
            [theImage drawInRect:r fromRect:NSZeroRect operation:NSCompositeSourceAtop fraction:fraction respectFlipped:YES hints:nil];
        }
    } else {
        NSAttributedString *atitle;
        NSFont *font;
        NSMutableDictionary *attr;
        [self superDrawRect:aRect];
        if (theTitle != nil) {
            //  We draw the title by ourselves and restore title
            NSControlSize controlSize = [[self cell] controlSize];
            font = [NSFont labelFontOfSize:[NSFont systemFontSizeForControlSize:controlSize]];
            attr = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    font, NSFontAttributeName,
                    nil];
            if (textColor != nil) {
                [attr setObject:textColor forKey:NSForegroundColorAttributeName];
            }
            atitle = [[NSAttributedString alloc] initWithString:theTitle attributes: attr];
            [atitle drawInRect:NSInsetRect(aRect, 4, 1)];
        }
    }
    [item setTitle:theTitle];
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

- (void)setBackgroundColor:(NSColor *)color
{
    [color retain];
    if (backgroundColor != nil)
        [backgroundColor release];
    backgroundColor = color;
}

- (NSColor *)backgroundColor
{
    return backgroundColor;
}

@end
