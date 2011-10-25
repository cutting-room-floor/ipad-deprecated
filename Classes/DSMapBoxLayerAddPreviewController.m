    //
//  DSMapBoxLayerAddPreviewController.m
//  MapBoxiPad
//
//  Created by Justin R. Miller on 5/18/11.
//  Copyright 2011 Development Seed. All rights reserved.
//

#import "DSMapBoxLayerAddPreviewController.h"

#import "DSMapView.h"
#import "RMTileStreamSource.h"
#import "DSMapContents.h"
#import "DSMapBoxTintedBarButtonItem.h"
#import "RMInteractiveSource.h"
#import "DSMapBoxDataOverlayManager.h"

@interface DSMapBoxLayerAddPreviewController ()

@property (nonatomic, retain) DSMapBoxDataOverlayManager *overlayManager;

@end

#pragma mark -

@implementation DSMapBoxLayerAddPreviewController

@synthesize mapView;
@synthesize metadataLabel;
@synthesize info;
@synthesize overlayManager;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = [NSString stringWithFormat:@"Preview %@", [info objectForKey:@"name"]];
    
    self.navigationItem.rightBarButtonItem = [[[DSMapBoxTintedBarButtonItem alloc] initWithTitle:@"Done"
                                                                                          target:self
                                                                                          action:@selector(dismissPreview:)] autorelease];
    
    // map view
    //
    NSArray *centerParts = [info objectForKey:@"center"];
    
    CLLocationCoordinate2D center = CLLocationCoordinate2DMake([[centerParts objectAtIndex:1] floatValue], [[centerParts objectAtIndex:0] floatValue]);
    
    RMTileStreamSource *source = [[[RMTileStreamSource alloc] initWithInfo:self.info] autorelease];
    
    [[[DSMapContents alloc] initWithView:self.mapView 
                              tilesource:source
                            centerLatLon:center
                               zoomLevel:([[centerParts objectAtIndex:2] floatValue] >= kLowerZoomBounds ? [[centerParts objectAtIndex:2] floatValue] : kLowerZoomBounds)
                            maxZoomLevel:[source maxZoom]
                            minZoomLevel:[source minZoom]
                         backgroundImage:nil] autorelease];
    
    self.mapView.enableRotate = NO;
    self.mapView.deceleration = NO;
    
    self.mapView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"loading.png"]];
    
    // setup interactivity manager
    //
    self.overlayManager = [[DSMapBoxDataOverlayManager alloc] initWithMapView:self.mapView];
    
    self.mapView.delegate = self.overlayManager;
    self.mapView.interactivityDelegate = self.overlayManager;
    
    // setup metadata label
    //
    NSMutableString *metadata = [NSMutableString string];

    if ([[self.info objectForKey:@"minzoom"] isEqual:[self.info objectForKey:@"maxzoom"]])
        [metadata appendString:[NSString stringWithFormat:@"  Zoom level %@", [self.info objectForKey:@"minzoom"]]];
    
    else
        [metadata appendString:[NSString stringWithFormat:@"  Zoom levels %@-%@", [self.info objectForKey:@"minzoom"], [self.info objectForKey:@"maxzoom"]]];
    
    if ([source supportsInteractivity])
        [metadata appendString:@", interactive"];

    if ([source coversFullWorld])
        [metadata appendString:@", full-world coverage"];
    
    self.metadataLabel.text = metadata;
    
    [TESTFLIGHT passCheckpoint:@"previewed TileStream layer"];
}

- (void)dealloc
{
    [mapView release];
    [metadataLabel release];
    [info release];
    [overlayManager release];
    
    [super dealloc];
}

#pragma mark -

- (void)dismissPreview:(id)sender
{
    [self.parentViewController dismissModalViewControllerAnimated:YES];
}

@end