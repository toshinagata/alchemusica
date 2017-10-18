//
//  NSMenuAdditions.m
//
//  Created by Toshi Nagata on 2017/10/12.
//
/*
    Copyright (c) 2004-2017 Toshi Nagata. All rights reserved.

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
    for (i = [ary count] - 1; i >= 0; i--) {
        NSMenuItem *item = [ary objectAtIndex:i];
        NSMenu *submenu;
        NSAttributedString *astr = [[[NSAttributedString alloc] initWithString:[item title] attributes:attributes] autorelease];
        [item setAttributedTitle:astr];
        submenu = [item submenu];
        if (submenu != nil)
            [submenu changeMenuTitleAttributes:attributes];
    }
}

@end
