/* MyWindow */

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

#import <Cocoa/Cocoa.h>

@interface MyWindow : NSWindow
{
	NSPoint lastMouseDownLocation;
}
- (NSPoint)lastMouseDownLocation;
@end

@protocol MyWindow
- (void)changeFirstResponderWithEvent: (NSEvent *)theEvent;
@end
