//
//  NSMenuAdditions.m
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

#import "NSMenuAdditions.h"


@implementation NSMenu (MyMenuAddition)

- (void)changeMenuTitleAttributes:(NSDictionary *)attributes
{
    int i;
    NSArray *ary = [self itemArray];
    for (i = (int)[ary count] - 1; i >= 0; i--) {
        NSMenuItem *item = [ary objectAtIndex:i];
        NSMenu *submenu;
        NSAttributedString *astr = [[[NSAttributedString alloc] initWithString:[item title] attributes:attributes] autorelease];
        [item setAttributedTitle:astr];
        submenu = [item submenu];
        if (submenu != nil)
            [submenu changeMenuTitleAttributes:attributes];
    }
}

static NSMenuItem *
searchMenuItemWithTagSub(NSMenu *menu, int tag)
{
    int i;
    NSMenuItem *item;
    for (i = (int)[menu numberOfItems] - 1; i >= 0; i--) {
        item = (NSMenuItem *)[menu itemAtIndex: i];
        if ([item tag] == tag)
            return item;
        if ([item hasSubmenu]) {
            item = searchMenuItemWithTagSub([item submenu], tag);
            if (item != nil)
                return item;
        }
    }
    return nil;
}

- (NSMenuItem *)searchMenuItemWithTag:(int)tag
{
    return searchMenuItemWithTagSub(self, tag);
}

- (NSMenu *)findSubmenuContainingItem:(NSMenuItem *)anItem outIndex:(int *)outIndex
{
    int i;
    NSMenuItem *item;
    for (i = (int)[self numberOfItems] - 1; i >= 0; i--) {
        item = (NSMenuItem *)[self itemAtIndex: i];
        if (item == anItem) {
            if (outIndex != NULL)
                *outIndex = i;
            return self;
        }
        if ([item hasSubmenu]) {
            NSMenu *menu = [[item submenu] findSubmenuContainingItem:anItem outIndex:outIndex];
            if (menu != nil)
                return menu;
        }
    }
    return nil;
}

@end
