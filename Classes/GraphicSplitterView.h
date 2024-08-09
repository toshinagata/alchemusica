//
//  GraphicSplitterView.h
//  Created by Toshi Nagata on Sun Feb 09 2003.
//
/*
    Copyright (c) 2003-2024 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>
#import "MyPopUpButton.h"

@interface GraphicSplitterView : NSView {
	MyPopUpButton *kindPopup;
	MyPopUpButton *codePopup;
    MyPopUpButton *trackPopup;
    MyPopUpButton *resolutionPopup;
    NSTextField *trackLabelText;
    NSTextField *resolutionLabelText;
    NSMenu *controlSubmenu;
}

- (void)setKindAndCode: (int32_t)kindAndCode;
- (void)setTrack: (int)track;
- (void)rebuildTrackPopup;

@end
