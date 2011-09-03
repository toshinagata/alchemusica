//
//  MyTableHeaderView.h
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

#import <Cocoa/Cocoa.h>

@interface MyTableHeaderView : NSTableHeaderView {
}
@end

@interface NSObject(MyTableHeaderViewDelegate)
- (NSMenu *)tableHeaderView:(NSTableHeaderView *)headerView popUpMenuAtHeaderColumn:(int)column;
@end
