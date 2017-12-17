//
//  MyComboBoxCell.m
//  Alchemusica
//
//  Created by Toshi Nagata on 06/05/08.
//  Copyright 2006-2011 Toshi Nagata. All rights reserved.
/*

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "MyComboBoxCell.h"
#import "MyPopUpButton.h"

@implementation MyComboBoxCell

#if MAC_OS_X_VERSION_MIN_REQUIRED == MAC_OS_X_VERSION_10_3
- (void)setControlView: (NSView *)view
{
	_controlView = view;
}
#endif

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    NSRect theRect, r;
	NSPoint center;
	NSString *theString;
	float fraction;
	lastDrawnRect = cellFrame;
	theRect = cellFrame;
	center.x = theRect.origin.x + theRect.size.width / 2;
	center.y = theRect.origin.y + theRect.size.height / 2;
	if ([self isEnabled])
		fraction = 1.0f;
	else fraction = 0.5f;
	switch ([self type]) {
		case NSTextCellType:
			theString = [self stringValue];
			if (theString != nil) {
				NSMutableParagraphStyle *par = [[[NSMutableParagraphStyle alloc] init] autorelease];
				NSFont *font = [NSFont systemFontOfSize: [NSFont smallSystemFontSize]];
				float lineHeight = [font ascender] - [font descender];
				NSRect rect = NSMakeRect(theRect.origin.x, theRect.origin.y + (theRect.size.height - lineHeight - 2), theRect.size.width, lineHeight + 2);
				[par setAlignment: NSCenterTextAlignment];
				[theString drawInRect: rect withAttributes: 
					[NSDictionary dictionaryWithObjectsAndKeys: 
						font,
						NSFontAttributeName,
						par,
						NSParagraphStyleAttributeName, nil]];
			}
			break;
		default:
			break;
	}
//	theRect = NSMakeRect(theRect.origin.x + theRect.size.width - 7, theRect.origin.y + theRect.size.height - 7, 5, 5);
    r.origin.x = theRect.origin.x + theRect.size.width - 7;
    r.origin.y = theRect.origin.y + theRect.size.height - 7;
    r.size.width = 5;
    r.size.height = 5;
    [[MyPopUpButton triangleImage] drawInRect:r fromRect:NSZeroRect operation:NSCompositeSourceAtop fraction:fraction respectFlipped:YES hints:nil];
}

@end
