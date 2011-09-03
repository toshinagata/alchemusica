//
//  AudioSettingsPanelController.h
//  Alchemusica
//
//  Created by Toshi Nagata on 10/06/13.
//  Copyright 2010-2011 Toshi Nagata. All rights reserved.
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

@interface AudioSettingsPanelController : NSWindowController {
	NSTimer *timer;				/*  Refresh the display periodically during playing  */
}
+ (void)openAudioSettingsPanel;
- (void)updateDisplay;
- (IBAction)myPopUpAction:(id)sender;
- (IBAction)volumeSliderMoved:(id)sender;
- (IBAction)panKnobMoved:(id)sender;
- (IBAction)customViewButtonPressed:(id)sender;
@end
