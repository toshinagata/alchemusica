//
//  MyTableHeaderView.m
//
//  Created by Toshi Nagata on Sun Jun 24 2001.
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

#import "MyTableHeaderView.h"

@implementation MyTableHeaderView

- (void)mouseDown:(NSEvent *)theEvent
{
	int column;
	NSPoint point;
	NSRect rect;
	NSMenu *menu;
	id delegate;
	point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
//	NSLog(@"Mouse down at %@ (view coordinate)\n", NSStringFromPoint(point));
	for (column = (int)[[self tableView] numberOfColumns] - 1; column >= 0; column--) {
		rect = [self headerRectOfColumn:column];
		rect = NSInsetRect(rect, 5.0f, 0.0f);
	//	NSLog(@"Column %d, rect %@\n", column, NSStringFromRect(rect));
		if (NSPointInRect(point, rect)) {
		//	NSBeep();
			delegate = [[self tableView] delegate];
			if (delegate != nil && [delegate respondsToSelector:@selector(tableHeaderView:popUpMenuAtHeaderColumn:)]) {
				menu = [delegate tableHeaderView:self popUpMenuAtHeaderColumn:column];
				if (menu != nil) {
					if ([NSMenu respondsToSelector: @selector(popUpContextMenu:withEvent:forView:withFont:)])
						/*  10.3-and-later-only method  */
						[NSMenu popUpContextMenu:menu withEvent:theEvent forView:self withFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
					else
						[NSMenu popUpContextMenu:menu withEvent:theEvent forView:self];
					return;
				}
			}
			break;
		}
	}
	[super mouseDown:theEvent];
}

@end
