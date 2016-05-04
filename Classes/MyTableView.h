//
//  MyTableView.h
//
//  Created by Toshi Nagata.
/*
    Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>

@interface MyTableView : NSTableView
{
	//  Maintaining text edit
	NSString *originalString;
	BOOL escapeFlag;
	
	//  Draw underline for one row
	int underlineRow;
}
- (void)setUnderlineRow:(int)row;
//- (BOOL)keyDown: (NSEvent *)theEvent onObject: (id)theObject;
@end

@interface NSObject (MyTableViewAddition)
- (BOOL)myTableView:(MyTableView *)tableView shouldEditColumn:(int)column row:(int)row;
@end
