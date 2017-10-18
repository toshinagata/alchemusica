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

#if defined(__LP64__) && __LP64__
#define USE_CARBON 0
#else
#define USE_CARBON 1
#endif

#import <Cocoa/Cocoa.h>
#import <AudioUnit/AudioUnit.h>
#import <AudioUnit/AudioUnitCarbonView.h>

@interface AUViewWindowController : NSWindowController <NSWindowDelegate> {
@public
	BOOL isProcessingCarbonEventHandler;  //  True while processing carbon event
@protected
	AudioUnit audioUnit;
#if USE_CARBON
	AudioUnitCarbonView auCarbonView;
#endif
	ComponentDescription viewCD;
	id _delegate;
	NSSize defaultViewSize;
	
#if USE_CARBON
	WindowRef carbonWindowRef;
#endif
}
+ (AUViewWindowController *)windowControllerForAudioUnit:(AudioUnit)unit cocoaView:(BOOL)cocoaView delegate:(id)delegate;
- (id)initWithAudioUnit:(AudioUnit)unit cocoaView:(BOOL)cocoaView delegate:(id)delegate;
- (AudioUnit)audioUnit;
+ (BOOL)error:(NSString *)errString status:(OSStatus)err;
+ (NSView *)getCocoaViewForAudioUnit:(AudioUnit)unit defaultViewSize:(NSSize)viewSize;
@end

@interface NSObject (AUViewWindowControllerProtocol)
- (void)auViewWindowWillClose: (id)auViewWindowController;
@end
