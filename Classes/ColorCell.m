//
//  ColorCell.m
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

#import "ColorCell.h"
#include <math.h>

@implementation ColorCell

- (id)copyWithZone: (NSZone *)zone
{
	id copiedSelf = [super copyWithZone: zone];
	if (copiedSelf != nil) {
		id rep = [self representedObject];
		if (rep != nil && [rep isKindOfClass: [NSColor class]])
			[copiedSelf setRepresentedObject: rep];
	}
	return copiedSelf;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	id image, rep;
	rep = [self representedObject];
	if (rep != nil && [rep isKindOfClass: [NSColor class]]) {
		[(NSColor *)rep set];
		if (!noFillsColor)
			NSRectFill(cellFrame);
		else if (!noStrokesColor)
			NSFrameRect(cellFrame);
	}
	image = [self objectValue];
	if (image != nil && [image isKindOfClass: [NSImage class]]) {
		NSRect r;
		NSSize sz = [(NSImage *)image size];
		r.origin.x = cellFrame.origin.x + (CGFloat)floor(cellFrame.size.width / 2 - sz.width / 2);
		r.origin.y = cellFrame.origin.y + (CGFloat)floor(cellFrame.size.height / 2 - sz.height / 2);
        r.size = sz;
	//	if ([[NSView focusView] isFlipped])
	//		pt.y += sz.height;
        [(NSImage *)image drawInRect: r fromRect: NSZeroRect operation: NSCompositeSourceAtop fraction: 1.0f respectFlipped:YES hints:nil];
	}
}

- (BOOL)fillsColor
{
	return !noFillsColor;
}

- (void)setFillsColor: (BOOL)flag
{
	noFillsColor = !flag;
}

- (BOOL)strokesColor
{
	return !noStrokesColor;
}

- (void)setStrokesColor: (BOOL)flag
{
	noStrokesColor = !flag;
}

@end
