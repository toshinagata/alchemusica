//
//  PianoRollRulerView.m
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

#import "PianoRollRulerView.h"
#import "MDHeaders.h"

@implementation PianoRollRulerView

- (void)dealloc
{
	[labels release];
	[super dealloc];
}

- (void)recalcLabels
{
	int index, n;
	[labels release];
	labels = [[NSMutableArray allocWithZone: [self zone]] initWithCapacity: 37];
	for (index = -17; index <= +19; index++) {
		char name[8];
		n = MDEventStaffIndexToNoteNumber(index);
		MDEventNoteNumberToNoteName(n, name);
	/*	[labels addObject:
			[[[NSCell allocWithZone: [self zone]]
				initTextCell: [NSString stringWithCString: name]] autorelease]]; */
        [labels addObject: [NSString stringWithCString: name]];
	}
}

- (void)drawRect:(NSRect)aRect
{
//	NSCell *cell;
	NSRect rect;
	float scale;
	NSPoint pt;
	int n, index;
	if (labels == nil)
		[self recalcLabels];
	rect = [self bounds];
	pt = NSMakePoint(rect.origin.x + rect.size.width - 0.5, rect.origin.y);
	[NSBezierPath strokeLineFromPoint: pt toPoint: NSMakePoint(pt.x, pt.y + rect.size.height)];
//	rect.size.height = 0.0;
	rect.origin.x = rect.origin.x + rect.size.width - 32.0;
    rect.size.height = [[GraphicRulerView rulerLabelFont] defaultLineHeightForFont];
	rect.size.width = 32.0;
	scale = [(GraphicClientView *)[self clientView] yScale];
	for (index = -17; index <= +19; index++) {
		n = MDEventStaffIndexToNoteNumber(index);
		if (n < 0 || n >= 128)
			continue;
        pt = [self convertPoint: NSMakePoint(0, n * scale) fromView: clientView];
        rect.origin.y = pt.y - rect.size.height * 0.2;
        if (NSIntersectsRect(rect, aRect)) {
            [[labels objectAtIndex: index + 17] drawAtPoint: rect.origin withAttributes: nil];
        }
/*		cell = (NSCell *)[labels objectAtIndex: index + 17];
		if (rect.size.height == 0.0) {
			rect.size.height = [[cell font] defaultLineHeightForFont];
			rect.origin.y = -rect.size.height * 2;
		}
		pt = [self convertPoint: NSMakePoint(0, n * scale) fromView: clientView];
		pt.y -= rect.size.height * 0.5;
		if (rect.origin.y + rect.size.height <= pt.y) {
			rect.origin.y = pt.y;
			[[cell stringValue] drawAtPoint: rect.origin withAttributes: nil];
		//	[cell drawInteriorWithFrame: rect inView: self];
		} */
	}
	[super drawRect:aRect];

/*	[[[self clientView] dataSource] setInfoText:
		[NSString stringWithFormat: @"frame %@, bounds %@, client: frame %@, bounds %@",
			NSStringFromRect([[self superview] frame]),
			NSStringFromRect([[self superview] bounds]),
			NSStringFromRect([[[self clientView] superview] frame]),
			NSStringFromRect([[[self clientView] superview] bounds])
			]]; */
}

@end
