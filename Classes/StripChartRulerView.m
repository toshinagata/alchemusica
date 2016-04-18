//
//  StripChartRulerView.m
//  Created by Toshi Nagata on Sun Jan 26 2003.
//
/*
    Copyright (c) 2003-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "StripChartRulerView.h"
#import "StripChartView.h"
#import "MDHeaders.h"

@implementation StripChartRulerView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
     }
    return self;
}

- (void)dealloc
{
	[super dealloc];
}

- (void)drawRect:(NSRect)aRect
{
	NSRect frame, bounds, visibleRect;
	NSFont *font;
	NSDictionary *attr;
	float grid;
	float minValue, maxValue, visibleMinValue, visibleMaxValue, visibleRange, aRange;
	int i, min, max;
	float ascender, descender, x, y, yval;
	NSString *str;
	frame = [self frame];
	bounds = [self bounds];
	visibleRect = [(NSClipView *)[self superview] documentVisibleRect];
	x = frame.size.width - 0.5;
	[NSBezierPath strokeLineFromPoint: NSMakePoint(x, 0) toPoint: NSMakePoint(x, bounds.size.height)];
	minValue = [(StripChartView *)[self clientView] minValue];
	maxValue = [(StripChartView *)[self clientView] maxValue];
	grid = [(StripChartView *)[self clientView] horizontalGridInterval];
	font = [[self class] rulerLabelFont];
	ascender = [font ascender];
	descender = [font descender];
	attr = [NSDictionary dictionaryWithObjectsAndKeys: font, NSFontAttributeName, nil];
	for (yval = minValue; yval <= maxValue + 1.00001; yval += grid) {
		y = floor(yval * bounds.size.height / (maxValue - minValue + 1.0));
		x = frame.size.width - 4.0;
		if (y > 0.0 && y < bounds.size.height)
			[NSBezierPath strokeLineFromPoint: NSMakePoint(x, y + 0.5) toPoint: NSMakePoint(x + 4.0, y + 0.5)];
		y -= floor((ascender - descender) / 2);
		if (y > aRect.origin.y + aRect.size.height + 1
		|| y < aRect.origin.y - (ascender - descender) - 1)
			continue;
		if (y > bounds.size.height - (ascender - descender))
			y = bounds.size.height - (ascender - descender);
		if (y < 0)
			y = 0;
		str = [NSString stringWithFormat: @"%g", (yval > maxValue ? maxValue : yval)];
		x = frame.size.width - 4.0 - [font widthOfString: str];
		[str drawAtPoint: NSMakePoint(x, y) withAttributes: attr];
	}
	[super drawRect:aRect];
}

@end
