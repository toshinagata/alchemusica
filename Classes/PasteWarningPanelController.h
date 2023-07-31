//
//  PasteWarningPanelController.h
//  Alchemusica
//
//  Created by Toshi Nagata on 2020/03/14.
//  Copyright 2020-2022 Toshi Nagata. All rights reserved.
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

enum {
    kPasteWarningTypeTooManyTargets = 1,
    kPasteWarningTypeTooFewTargets,
    kPasteWarningTypeConductorShouldBeEditable,
    kPasteWarningTypeConductorShouldNotBeEditable
};

@interface PasteWarningPanelController : NSWindowController {
    IBOutlet NSTextField *mainMessage;
    IBOutlet NSButton *radio1;
    IBOutlet NSButton *radio2;
    int returnCode;
    int type;
}
+ (id)createPasteWarningPanelControllerOfType:(int)aType;
- (void)setMainMessageWithInteger:(int)n1 and:(int)n2;
- (int)runSheetModalWithWindow:(NSWindow *)window;
- (IBAction)radioSelected:(id)sender;
- (IBAction)cancelPressed:(id)sender;
- (IBAction)pastePressed:(id)sender;

@end
