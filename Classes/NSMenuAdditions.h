//
//  NSMenuAdditions.h
//
//  Created by Toshi Nagata on 2017/10/12.
//
/*
    Copyright (c) 2004-2024 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>

@interface NSMenu (MyMenuAddition)
- (void)changeMenuTitleAttributes:(NSDictionary *)attributes;
- (NSMenuItem *)searchMenuItemWithTag:(int)tag;
- (NSMenu *)findSubmenuContainingItem:(NSMenuItem *)anItem outIndex:(int *)outIndex;
@end
