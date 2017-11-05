//
//  MyPopUpButton.h
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

/*  MyPopUpButton: A compact popup button which shows an image and a small disclosure
    triangle  */

#import <Cocoa/Cocoa.h>

@interface MyPopUpButton : NSPopUpButton
{
    NSColor *textColor;
    NSColor *backgroundColor;
}
+ (NSImage *)triangleImage;
+ (NSImage *)doubleTriangleImage;
- (void)drawRect: (NSRect)aRect;
- (void)setTextColor: (NSColor *)color;
- (void)setBackgroundColor:(NSColor *)color;
- (NSColor *)textColor;
- (NSColor *)backgroundColor;
@end
