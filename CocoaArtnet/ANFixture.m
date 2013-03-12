//
//  ANFixture.m
//  CocoaArtnet
//
//  Created by Phil Christensen on 2/25/13.
//  Copyright (c) 2013 Phil Christensen. All rights reserved.
//

#import "ANFixture.h"
#import <YACYAML/YACYAML.h>
#import <UIKit/UIColor.h>

@implementation ANFixture
@synthesize address;
@synthesize controls;

-(ANFixture*) initWithAddress: (int) anAddress {
    self = [super init];
    self.address = anAddress;
    self.controls = [[NSMutableDictionary alloc] init];
    return self;
}

+(ANFixture*) createWithAddress: (int) anAddress andFixturePath: (NSString*) aPath {
    ANFixture* fixture = [[ANFixture alloc] initWithAddress:anAddress];
    [fixture loadFixtureDefinition:aPath];
    return fixture;
}

-(void) loadFixtureDefinition: (NSString*) fixturePath {
    
    NSString* yaml = [[NSString alloc] initWithContentsOfFile:fixturePath
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
    NSDictionary* fixturedef = [YACYAMLKeyedUnarchiver unarchiveObjectWithString:yaml];
    [controls setValue: [[RGBControl alloc] initWith: fixturedef] forKey:@"rgb"];
    [controls setValue: [[StrobeControl alloc] initWith: fixturedef] forKey:@"strobe"];
    [controls setValue: [[IntensityControl alloc] initWith: fixturedef] forKey:@"intensity"];
    for(NSDictionary* channel in fixturedef[@"program_channels"]){
        [controls setValue: [[ProgramControl alloc] initWith:fixturedef andChannel:channel]
                    forKey: [NSString stringWithFormat:@"program-%d",
                             [channel[@"offset"] integerValue]
                             ]
         ];
    }
}

-(void) forwardInvocation:(NSInvocation *)anInvocation {
    SEL aSelector = [anInvocation selector];
    
    for (NSString* key in self.controls) {
        id ctl = self.controls[key];
        if([ctl respondsToSelector:aSelector]){
            [anInvocation invokeWithTarget:ctl];
            return;
        }
    }
    [super forwardInvocation:anInvocation];
}

-(NSMethodSignature *) methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature* signature = [super methodSignatureForSelector:aSelector];
    if(signature) {
        return signature;
    }
    
    for (NSString* key in self.controls) {
        id ctl = self.controls[key];
        if([ctl respondsToSelector:aSelector]){
            return [[ctl class] instanceMethodSignatureForSelector:aSelector];
        }
    }
    return nil;
}

-(NSArray*) getState {
    NSMutableArray* state = [[NSMutableArray alloc] init];
    for(NSString* key in [[self.controls allKeys] sortedArrayUsingComparator: ^(id a, id b){
        return ([a hasPrefix:@"program-"] ? (NSComparisonResult)NSOrderedDescending : (NSComparisonResult)NSOrderedAscending);
    }]){
        id ctl = self.controls[key];
        [state addObjectsFromArray:[ctl getState]];
    }
    return state;
}

-(NSArray*) getFrame {
    NSMutableArray* frame = [[NSMutableArray alloc] init];
    for(int i = 0; i < 512; i++){
        frame[i] = @0;
    }
    for(NSArray* channelSet in [self getState]){
        frame[[channelSet[0] integerValue] + self.address - 1] = channelSet[1];
    }
    return frame;
}

@end

@implementation RGBControl
@synthesize r_value;
@synthesize g_value;
@synthesize b_value;
@synthesize r_offset;
@synthesize g_offset;
@synthesize b_offset;

-(RGBControl*) initWith: (NSDictionary*) fixturedef {
	self = [super init];
    self.r_offset = [fixturedef[@"rgb_offsets"][@"red"] integerValue];
    self.g_offset = [fixturedef[@"rgb_offsets"][@"green"] integerValue];
    self.b_offset = [fixturedef[@"rgb_offsets"][@"blue"] integerValue];
    self.r_value = 0;
    self.g_value = 0;
    self.b_value = 0;
    return self;
}

-(NSArray*) getState {
	return @[
          @[@(self.r_offset), @(self.r_value)],
          @[@(self.g_offset), @(self.g_value)],
          @[@(self.b_offset), @(self.b_value)]
          ];
}

-(void) setColor:(NSString*) hexcolor {
    NSScanner* scanner = [NSScanner scannerWithString:hexcolor];
    unsigned int hex;
    if ([scanner scanHexInt:&hex]) {
        // Parsing successful. We have a big int representing the 0xBD8F60 value
        self.r_value = (hex >> 16) & 0xFF; // get the first byte
        self.g_value = (hex >>  8) & 0xFF; // get the middle byte
        self.b_value = (hex      ) & 0xFF; // get the last byte
    } else {
        NSLog(@"Parsing error: no hex value found in string");
    }
}

-(NSString*) getColor {
	return [NSString stringWithFormat:@"#%02x%02x%02x",
            self.r_value, self.g_value, self.b_value];
}

@end

@implementation StrobeControl
@synthesize offset;
@synthesize value;

-(StrobeControl*) initWith: (NSDictionary*) fixturedef {
	self = [super init];
    self.offset = [fixturedef[@"strobe_offset"] integerValue];
    self.value = 0;
    return self;
}

-(NSArray*) getState {
	return @[
          @[@(self.offset), @(self.value)]
          ];
}

-(void) setStrobe:(int) level {
	self.value = level;
}

-(int) getStrobe {
	return self.value;
}

@end

@implementation IntensityControl
@synthesize offset;
@synthesize offset_fine;
@synthesize value;

-(IntensityControl*) initWith: (NSDictionary*) fixturedef {
	self = [super init];
    self.offset = [fixturedef[@"intensity_offset"] integerValue];
    self.value = 0;
    return self;
}

-(NSArray*) getState {
	return @[
          @[@(self.offset), @(self.value)]
          ];
}

-(void) setIntensity:(int) level {
	self.value = level;
}

-(int) getIntensity {
	return self.value;
}

@end

@implementation ProgramControl
@synthesize offset;
@synthesize speedOffset;
@synthesize value;
@synthesize speedValue;
@synthesize macroType;
@synthesize macros;

-(ProgramControl*) initWith: (NSDictionary*) fixturedef andChannel: (NSDictionary*) channel {
	self = [super init];
    
    self.offset = [channel[@"offset"] integerValue];
    self.macroType = channel[@"type"];
    if([self.macroType isEqualToString:@"program"]){
        id o = [channel objectForKey:@"speed_offset"];
        if(o == nil){
            self.speedOffset = [[fixturedef objectForKey:@"strobe_offset"] intValue];
        }
        else{
            self.speedOffset = [o intValue];
        }
    }
    
    
    for(NSString* label in channel[@"macros"]){
        id conf = channel[@"macros"][label];
        if([conf isKindOfClass:[NSNumber class]]){
            [self setMacro:label withValue:[conf integerValue]];
        }
        else{
            [self setMacro:label withValue:[conf[@"value"] integerValue] andSpeed:[conf[@"speed"] integerValue]];
        }
    }
    
    return self;
}

-(NSArray*) getState {
    if(self.speedOffset){
        return @[
                 @[@(self.offset), @(self.value)],
                 @[@(self.speedOffset), @(self.speedValue)]
                 ];
    }
    else{
        return @[
              @[@(self.offset), @(self.value)],
              ];
    }
}

-(void) setMacro: (NSString*) macroName withValue: (int) aValue andSpeed: (int) aSpeed {
    self.macros[macroName] = @[@(aValue), @(aSpeed)];
}

-(void) setMacro: (NSString*) macroName withValue: (int) aValue {
    self.macros[macroName] = @[@(aValue), [NSNull null]];
}

@end
