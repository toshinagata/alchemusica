//
//  TrackAttributeCell.h
//
/*
    Copyright (c) 2000-2022 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>


@interface TrackAttributeCell : NSActionCell {
    int startPartCode, currentPartCode, partCode;
    NSRect startCellFrame;
}
+ (int)lastPartCode;

@end
