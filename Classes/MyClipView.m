//
//  MyClipView.m
//  Alchemusica
//
//  Created by Toshi Nagata on 2017/10/09.
//
//

#import "MyClipView.h"

@implementation MyClipView

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)rect
{
    NSDrawWindowBackground(rect);
}

@end
