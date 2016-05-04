/*
 Copyright 2000-2016 Toshi Nagata.  All rights reserved.
 
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "MyWindow.h"

@implementation MyWindow

- (void)sendEvent:(NSEvent *)theEvent
{
	if ([theEvent type] == NSLeftMouseDown) {
		id delegate = [self delegate];
		lastMouseDownLocation = [theEvent locationInWindow];
		if (delegate != nil && [delegate respondsToSelector: @selector(changeFirstResponderWithEvent:)]) {
			[delegate changeFirstResponderWithEvent: theEvent];
		}
	}
	[super sendEvent: theEvent];
}

- (NSPoint)lastMouseDownLocation
{
	return lastMouseDownLocation;
}

@end
