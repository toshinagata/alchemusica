//
//  GraphicSplitterView.h
//  Created by Toshi Nagata on Sun Feb 09 2003.
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

#import <Cocoa/Cocoa.h>


@interface GraphicSplitterView : NSView {
	NSPopUpButton *kindPopup;
	NSTextField *kindText;
	NSPopUpButton *codePopup;
	NSTextField *codeText;
}

- (void)setKindAndCode: (long)kindAndCode;
//- (long)kindAndCode;

@end
