//
//  GraphicFloatingView.m
//  Created by Toshi Nagata on Thu Apr 24 2003.
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

#import "GraphicFloatingView.h"
#import "GraphicWindowController.h"

@implementation GraphicFloatingView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (NSView *)hitTest: (NSPoint)aPoint
{
	//  Ignore any mouse down events inside this view
	return nil;
}

@end
