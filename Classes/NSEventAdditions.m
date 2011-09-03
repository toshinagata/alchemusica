//
//  NSEventAdditions.m
//
//  Created by Toshi Nagata on Sun Apr 25 2004.
//
/*
    Copyright (c) 2004-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "NSEventAdditions.h"


@implementation NSEvent (MyEventAddition)

- (NSEvent *)mouseEventWithLocation: (NSPoint)pt
{
    return [NSEvent mouseEventWithType: [self type] location: pt modifierFlags: [self modifierFlags] timestamp: [self timestamp] windowNumber: [self windowNumber] context: [self context] eventNumber: [self eventNumber] clickCount: [self clickCount] pressure: [self pressure]];
}

@end
