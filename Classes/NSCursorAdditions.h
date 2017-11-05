//
//  NSCursorAdditions.h
//  Alchemusica
//
//  Created by Toshi Nagata on Sun Nov 21 2004.
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

#import <Cocoa/Cocoa.h>

@interface NSCursor (MyCursorAddition)
+ (NSCursor *)horizontalMoveCursor;
+ (NSCursor *)verticalMoveCursor;
+ (NSCursor *)horizontalMovePlusCursor;
+ (NSCursor *)horizontalMoveZoomCursor;
+ (NSCursor *)verticalMovePlusCursor;
+ (NSCursor *)stretchCursor;
+ (NSCursor *)moveAroundCursor;
+ (NSCursor *)loupeCursor;
+ (NSCursor *)pencilCursor;
+ (NSCursor *)speakerCursor;
@end
