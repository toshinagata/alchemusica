//
//  AUViewWindowController.h
//  Alchemusica
//
//  Created by Toshi Nagata on 10/06/26.
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
#import <AudioUnit/AudioUnit.h>
#import <AudioUnit/AudioUnitCarbonView.h>

@interface AUViewWindowController : NSWindowController <NSWindowDelegate> {
@public
	BOOL isProcessingCarbonEventHandler;  //  True while processing carbon event
@protected
	AudioUnit audioUnit;
	AudioUnitCarbonView auCarbonView;
	ComponentDescription viewCD;
	id _delegate;
	NSSize defaultViewSize;
	
//	NSWindow *cocoaWindow;
	WindowRef carbonWindowRef;
//	NSWindow *carbonWindow;  //  For adding Windows menu item
}
+ (AUViewWindowController *)windowControllerForAudioUnit:(AudioUnit)unit cocoaView:(BOOL)cocoaView delegate:(id)delegate;
- (id)initWithAudioUnit:(AudioUnit)unit cocoaView:(BOOL)cocoaView delegate:(id)delegate;
- (AudioUnit)audioUnit;
/*
- (int)showCocoaViewForAudioUnit:(AudioUnit)anAudioUnit;
- (int)showCarbonViewForAudioUnit:(AudioUnit)anAudioUnit;
+ (id)windowControllerForAudioUnit: (AudioUnit)anAudioUnit;
*/
@end

@interface NSObject (AUViewWindowControllerProtocol)
- (void)auViewWindowWillClose: (id)auViewWindowController;
@end
