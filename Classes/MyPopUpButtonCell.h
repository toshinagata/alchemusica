//
//  MyPopUpButtonCell.h
//  Alchemusica
//
//  Created by Toshi Nagata on 06/05/07.
//  Copyright 2006-2024 Toshi Nagata. All rights reserved.
//
/*
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>

@interface MyPopUpButtonCell : NSPopUpButtonCell {
}
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;

@end
