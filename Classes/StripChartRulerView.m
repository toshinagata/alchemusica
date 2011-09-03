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
	NSRect frame, bounds;
	NSFont *font;
	NSDictionary *attr;
	float minValue, maxValue, visibleRange, aRange;
	int i, min, max;
	float ascender, descender, x, y;
	NSString *str;
	frame = [self frame];
	bounds = [self bounds];
	x = frame.size.width - 0.5;
	[NSBezierPath strokeLineFromPoint: NSMakePoint(x, 0) toPoint: NSMakePoint(x, frame.size.height)];
	minValue = [(StripChartView *)[self clientView] minValue];
	maxValue = [(StripChartView *)[self clientView] maxValue];
	visibleRange = (maxValue - minValue) / frame.size.height * bounds.size.height;
	aRange = maxValue - minValue;
	while (aRange > visibleRange * 0.7)
		aRange *= 0.5;
	minValue += (maxValue - minValue) / frame.size.height * bounds.origin.y;
	maxValue = minValue + visibleRange;
	min = minValue / aRange - 1;
	max = maxValue / aRange + 1;
	font = [[self class] rulerLabelFont];
	ascender = [font ascender];
	descender = [font descender];
	attr = [NSDictionary dictionaryWithObjectsAndKeys: font, NSFontAttributeName, nil];
	for (i = min; i <= max; i++) {
		y = floor((i * aRange - minValue) * bounds.size.height / visibleRange);
		x = frame.size.width - 4.0;
		if (y > 0.0 && y < frame.size.height)
			[NSBezierPath strokeLineFromPoint: NSMakePoint(x, y + 0.5) toPoint: NSMakePoint(x + 4.0, y + 0.5)];
		y -= floor((ascender - descender) / 2);
		if (y > bounds.origin.y + bounds.size.height + 1
		|| y < bounds.origin.y - (ascender - descender) - 1)
			continue;
		if (y > frame.size.height - (ascender - descender))
			y = frame.size.height - (ascender - descender);
		if (y < 0)
			y = 0;
	//	y += (ascender + descender) / 2;
		str = [NSString stringWithFormat: @"%g", (float)floor(i * aRange + 0.5)];
		x = frame.size.width - 4.0 - [font widthOfString: str];
		[str drawAtPoint: NSMakePoint(x, y) withAttributes: attr];
	}
}

@end
