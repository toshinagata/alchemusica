//
//  AudioSettingsPrefPanelController.h
//  Alchemusica
//
//  Created by Toshi Nagata on 2019/07/21.
//  Copyright 2010-2024 Toshi Nagata. All rights reserved.
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

@interface AudioSettingsPrefPanelController : NSWindowController {
    IBOutlet NSPopUpButton *devicePopUp;
    IBOutlet NSButton *internalCheck;
    IBOutlet NSButton *applicationCheck;
    IBOutlet NSButton *selectButton;
    IBOutlet NSTextField *applicationPath;
    NSMutableArray *settings;
}
+ (void)openAudioSettingsPrefPanel;
+ (AudioSettingsPrefPanelController *)sharedAudioSettingsPrefPanelController;
+ (BOOL)shouldSaveInternalForDeviceName:(const char *)name;
+ (NSString *)shouldCallApplicationForDeviceName:(const char *)name;
- (void)updateDisplay;
- (IBAction)devicePopUpSelected:(id)sender;
- (IBAction)selectApplication:(id)sender;
- (IBAction)checkBoxClicked:(id)sender;
- (IBAction)cancelClicked:(id)sender;
- (IBAction)saveClicked:(id)sender;
@end
