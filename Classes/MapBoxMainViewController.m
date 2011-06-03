//
//  MapBoxMainViewController.m
//  MapBoxiPadDemo
//
//  Created by Justin R. Miller on 6/17/10.
//  Copyright Code Sorcery Workshop 2010. All rights reserved.
//

#import "MapBoxMainViewController.h"

#import "MapBoxConstants.h"

#import "DSMapView.h"
#import "DSMapBoxTileSetManager.h"
#import "DSMapBoxDataOverlayManager.h"
#import "DSMapContents.h"
#import "DSMapBoxDocumentSaveController.h"
#import "DSMapBoxMarkerManager.h"
#import "DSMapBoxHelpController.h"
#import "DSMapBoxFeedParser.h"
#import "DSMapBoxLayerAddNavigationController.h"
#import "DSMapBoxLayerAddTileStreamBrowseController.h"

#import "UIApplication_Additions.h"
#import "UIAlertView_Additions.h"

#import "SimpleKML.h"

#import "RMTileSource.h"
#import "RMOpenStreetMapSource.h"
#import "RMMBTilesTileSource.h"
#import "RMTileStreamSource.h"

#import "TouchXML.h"

#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

#import "Reachability.h"

@interface MapBoxMainViewController (MapBoxMainViewControllerPrivate)

void MapBoxMainViewController_SoundCompletionProc (SystemSoundID sound, void *clientData);
- (void)offlineAlert;
- (UIImage *)mapSnapshot;
- (void)layerImportAlertWithName:(NSString *)name;

@end

#pragma mark -

@implementation MapBoxMainViewController

@synthesize badParsePath;
@synthesize lastLayerAlertDate;

- (void)viewDidLoad
{
    [super viewDidLoad];

    // starting setup info
    //
    CLLocationCoordinate2D startingPoint;
    
    startingPoint.latitude  = kStartingLat;
    startingPoint.longitude = kStartingLon;
    
    // base map view
    //
    NSObject <RMTileSource>*source;
    
    NSURL *activeTileSetURL = [[DSMapBoxTileSetManager defaultManager] activeTileSetURL];
    
    if ([activeTileSetURL isEqual:kDSOpenStreetMapURL])
        source = [[[RMOpenStreetMapSource alloc] init] autorelease];

    else if ([activeTileSetURL isTileStreamURL])
        source = [[[RMTileStreamSource alloc] initWithInfo:[NSDictionary dictionaryWithContentsOfURL:activeTileSetURL]] autorelease];

    else
        source = [[[RMMBTilesTileSource alloc] initWithTileSetURL:[[DSMapBoxTileSetManager defaultManager] activeTileSetURL]] autorelease];
    
	[[[DSMapContents alloc] initWithView:mapView 
                              tilesource:source
                            centerLatLon:startingPoint
                               zoomLevel:kStartingZoom
                            maxZoomLevel:[source maxZoom]
                            minZoomLevel:[source minZoom]
                         backgroundImage:nil] autorelease];
    
    mapView.enableRotate = NO;
    mapView.deceleration = NO;
    
    mapView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"loading.png"]];

    mapView.contents.zoom = kStartingZoom;

    // data overlay & layer managers
    //
    dataOverlayManager = [[DSMapBoxDataOverlayManager alloc] initWithMapView:mapView];
    dataOverlayManager.mapView = mapView;
    mapView.delegate = dataOverlayManager;
    mapView.interactivityDelegate = dataOverlayManager;
    layerManager = [[DSMapBoxLayerManager alloc] initWithDataOverlayManager:dataOverlayManager overBaseMapView:mapView];
    layerManager.delegate = self;
    
    // watch for tile changes
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tileSetDidChange:)
                                                 name:DSMapBoxTileSetChangedNotification
                                               object:nil];
    
    // watch for net changes
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityDidChange:)
                                                 name:kReachabilityChangedNotification
                                               object:nil];
    
    reachability = [[Reachability reachabilityForInternetConnection] retain];
    [reachability startNotifier];
    
    // watch for zoom bounds limits
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(zoomBoundsReached:)
                                                 name:DSMapContentsZoomBoundsReached
                                               object:nil];
    
    self.lastLayerAlertDate = [NSDate date];
    
    // watch for new layer additions
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(layersAdded:)
                                                 name:DSMapBoxLayersAdded
                                               object:nil];
    
    // restore app state
    //
    [self restoreState:self];
    
    // warn about any zipped mbtiles
    //
    BOOL showedZipAlert = NO;
    
    NSPredicate *zippedPredicate = [NSPredicate predicateWithFormat:@"self ENDSWITH '.mbtiles.zip'"];
    
    NSArray *zippedTiles = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[UIApplication sharedApplication] documentsFolderPathString]
                                                                                error:NULL] filteredArrayUsingPredicate:zippedPredicate];
    
    NSMutableSet *seenZips = [NSMutableSet set];
    
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"seenZippedTiles"])
        [seenZips addObjectsFromArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"seenZippedTiles"]];
    
    for (NSString *zippedTile in zippedTiles)
    {
        if ( ! [seenZips containsObject:zippedTile] && ! showedZipAlert)
        {
            NSString *appName = [[NSProcessInfo processInfo] processName];
            
            [seenZips addObject:zippedTile];
            
            UIAlertView *zipAlert = [[[UIAlertView alloc] initWithTitle:@"Zipped Tiles Found"
                                                                message:[NSString stringWithFormat:@"Your %@ documents contain zipped tiles. Please unzip these tiles first in order to use them in %@.", appName, appName] 
                                                               delegate:nil
                                                      cancelButtonTitle:nil
                                                      otherButtonTitles:@"OK", nil] autorelease];
            
            [zipAlert show];
            
            showedZipAlert = YES;
        }
    }
    
    // make sure online tiles folder exists
    //
    NSString *onlineLayersFolder = [NSString stringWithFormat:@"%@/Online Layers", [[UIApplication sharedApplication] preferencesFolderPathString]];

    [[NSFileManager defaultManager] createDirectoryAtPath:onlineLayersFolder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    
    // set clustering button title
    //
    if (((DSMapBoxMarkerManager *)[mapView topMostMapView].contents.markerManager).clusteringEnabled)
        clusteringButton.title = @"Turn Clustering Off";

    else
        clusteringButton.title = @"Turn Clustering On";

    [[NSUserDefaults standardUserDefaults] setObject:[seenZips allObjects] forKey:@"seenZippedTiles"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    postRotationMapCenter = mapView.contents.mapCenter;
    
    return YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    mapView.contents.mapCenter = postRotationMapCenter;
    
    if ([mapView.contents isKindOfClass:[DSMapContents class]])
        [mapView.contents performSelector:@selector(postZoom) 
                               withObject:nil 
                               afterDelay:0.1];
    
    [mapView.delegate mapViewRegionDidChange:mapView]; // trigger popover move
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapBoxTileSetChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification   object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapContentsZoomBoundsReached     object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapBoxLayersAdded                object:nil];
    
    [reachability stopNotifier];
    [reachability release];
    
    [layersPopover release];
    [layerManager release];
    [dataOverlayManager release];
    [badParsePath release];
    [documentsActionSheet release];
    [lastLayerAlertDate release];

    [super dealloc];
}

#pragma mark -

- (void)restoreState:(id)sender
{
    NSDictionary *baseMapState;
    NSArray *tileOverlayState;
    NSArray *dataOverlayState;
    
    // determine if document or global restore
    //
    if ([sender isKindOfClass:[NSString class]])
    {
        NSString *saveFile = [NSString stringWithFormat:@"%@/%@/%@.plist", [[UIApplication sharedApplication] preferencesFolderPathString], kDSSaveFolderName, sender];
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:saveFile];
        
        baseMapState      = [dict objectForKey:@"baseMapState"];
        tileOverlayState  = [dict objectForKey:@"tileOverlayState"];
        dataOverlayState  = [dict objectForKey:@"dataOverlayState"];
    }
    else
    {
        baseMapState      = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"baseMapState"];
        tileOverlayState  = [[NSUserDefaults standardUserDefaults] arrayForKey:@"tileOverlayState"];
        dataOverlayState  = [[NSUserDefaults standardUserDefaults] arrayForKey:@"dataOverlayState"];
    }

    // load it up
    //
    if (baseMapState)
    {
        // get map center & zoom level
        //
        CLLocationCoordinate2D mapCenter = {
            .latitude  = [[baseMapState objectForKey:@"centerLatitude"]  floatValue],
            .longitude = [[baseMapState objectForKey:@"centerLongitude"] floatValue],
        };
        
        if (mapCenter.latitude <= kUpperLatitudeBounds && mapCenter.latitude >= kLowerLatitudeBounds)
            mapView.contents.mapCenter = mapCenter;
        
        if ([[baseMapState objectForKey:@"zoomLevel"] floatValue] >= kLowerZoomBounds && 
            [[baseMapState objectForKey:@"zoomLevel"] floatValue] <= kMBTilesDefaultMaxTileZoom)
            mapView.contents.zoom = [[baseMapState objectForKey:@"zoomLevel"] floatValue];
        
        // get base tile set
        //
        NSURL *restoreTileSetURL = [NSURL fileURLWithPath:[baseMapState objectForKey:@"tileSetURL"]];
        
        // apply base, if able
        //
        if ([[NSFileManager defaultManager] fileExistsAtPath:[restoreTileSetURL relativePath]] || [restoreTileSetURL isEqual:kDSOpenStreetMapURL])
        {        
            NSString *restoreTileSetName = [[DSMapBoxTileSetManager defaultManager] displayNameForTileSetAtURL:restoreTileSetURL];
            
            if (([restoreTileSetName isEqualToString:kDSOpenStreetMapName] || [restoreTileSetURL isTileStreamURL]) && 
                [reachability currentReachabilityStatus] == NotReachable)
                [self offlineAlert];
            
            else
                [[DSMapBoxTileSetManager defaultManager] makeTileSetWithNameActive:restoreTileSetName animated:NO];
        }
    }
    
    // load tile overlay state(s)
    //
    if (tileOverlayState)
    {
        // remove current layers
        //
        NSArray *activeTileLayers = [layerManager.tileLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"selected = YES"]];
        for (NSDictionary *tileLayer in activeTileLayers)
            [layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[layerManager.tileLayers indexOfObject:tileLayer]
                                                                    inSection:DSMapBoxLayerSectionTile]];
        
        // toggle new ones
        //
        for (NSString *tileOverlayURLString in tileOverlayState)
        {
            NSURL *tileOverlayURL = [NSURL fileURLWithPath:tileOverlayURLString];
            
            for (NSDictionary *tileLayer in layerManager.tileLayers)
                if ([[tileLayer objectForKey:@"URL"] isEqual:tileOverlayURL] &&
                    [[NSFileManager defaultManager] fileExistsAtPath:[tileOverlayURL relativePath]])
                    [layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[layerManager.tileLayers indexOfObject:tileLayer] 
                                                                            inSection:DSMapBoxLayerSectionTile]];
        }
    }
    
    // load data overlay state(s)
    //
    if (dataOverlayState)
    {
        // remove current layers
        //
        NSArray *activeDataLayers = [layerManager.dataLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"selected = YES"]];
        for (NSDictionary *dataLayer in activeDataLayers)
            [layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[layerManager.dataLayers indexOfObject:dataLayer]
                                                                    inSection:DSMapBoxLayerSectionData]];

        // toggle new ones
        //
        for (NSString *dataOverlayURLString in dataOverlayState)
        {
            NSURL *dataOverlayURL = [NSURL fileURLWithPath:dataOverlayURLString];
            
            for (NSDictionary *dataLayer in layerManager.dataLayers)
                if ([[dataLayer objectForKey:@"URL"] isEqual:dataOverlayURL] &&
                    [[NSFileManager defaultManager] fileExistsAtPath:[dataOverlayURL relativePath]])
                    [layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[layerManager.dataLayers indexOfObject:dataLayer] 
                                                                            inSection:DSMapBoxLayerSectionData]];
        }
    }

    // dismiss document loader
    //
    if ([sender isKindOfClass:[NSString class]])
        [self dismissModalViewControllerAnimated:YES];
}

- (void)saveState:(id)sender
{
    // get snapshot
    //
    NSData *mapSnapshot = UIImageJPEGRepresentation([self mapSnapshot], 1.0);
    
    // get base map state
    //
    NSDictionary *baseMapState = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [[[DSMapBoxTileSetManager defaultManager] activeTileSetURL] relativePath], @"tileSetURL",
                                     [NSNumber numberWithFloat:mapView.contents.mapCenter.latitude],            @"centerLatitude",
                                     [NSNumber numberWithFloat:mapView.contents.mapCenter.longitude],           @"centerLongitude",
                                     [NSNumber numberWithFloat:mapView.contents.zoom],                          @"zoomLevel",
                                     nil];
    
    // get tile overlay state(s)
    //
    NSArray *tileOverlayState = [((DSMapContents *)mapView.contents).layerMapViews valueForKeyPath:@"tileSetURL.relativePath"];
    
    // get data overlay state(s)
    //
    NSArray *dataOverlayState = [[layerManager.dataLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"selected = YES"]] valueForKeyPath:@"URL.relativePath"];

    // determine if document or global save
    //
    if ([sender isKindOfClass:[UIBarButtonItem class]] || [sender isKindOfClass:[NSString class]])
    {
        NSString *saveFolderPath = [DSMapBoxDocumentLoadController saveFolderPath];
        
        BOOL isDirectory = NO;
        
        if ( ! [[NSFileManager defaultManager] fileExistsAtPath:saveFolderPath isDirectory:&isDirectory] || ! isDirectory)
            [[NSFileManager defaultManager] createDirectoryAtPath:saveFolderPath 
                                      withIntermediateDirectories:YES 
                                                       attributes:nil
                                                            error:NULL];
        
        NSString *stateName;
        
        if ([sender isKindOfClass:[UIBarButtonItem class]]) // button save
            stateName = saveController.name;
        
        else if ([sender isKindOfClass:[NSString class]]) // load controller save
            stateName = sender;
        
        if ([stateName length] && [[stateName componentsSeparatedByString:@"/"] count] < 2) // no slashes
        {
            if ( ! tileOverlayState)
                tileOverlayState = [NSArray array];
            
            if ( ! dataOverlayState)
                dataOverlayState = [NSArray array];
            
            NSDictionary *state = [NSDictionary dictionaryWithObjectsAndKeys:mapSnapshot,      @"mapSnapshot", 
                                                                             baseMapState,     @"baseMapState", 
                                                                             tileOverlayState, @"tileOverlayState", 
                                                                             dataOverlayState, @"dataOverlayState", 
                                                                             nil];
            
            NSString *savePath = [NSString stringWithFormat:@"%@/%@.plist", saveFolderPath, stateName];
            
            [state writeToFile:savePath atomically:YES];
            
            if (self.modalViewController.modalPresentationStyle == UIModalPresentationFormSheet) // save panel
                [self dismissModalViewControllerAnimated:YES];
        }
    }
    else
    {
        [[NSUserDefaults standardUserDefaults] setObject:mapSnapshot      forKey:@"mapSnapshot"];
        [[NSUserDefaults standardUserDefaults] setObject:baseMapState     forKey:@"baseMapState"];
        [[NSUserDefaults standardUserDefaults] setObject:tileOverlayState forKey:@"tileOverlayState"];
        [[NSUserDefaults standardUserDefaults] setObject:dataOverlayState forKey:@"dataOverlayState"];

        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (IBAction)tappedDocumentsButton:(id)sender
{
    if (layersPopover.popoverVisible)
        [layersPopover dismissPopoverAnimated:NO];

    if ( ! documentsActionSheet || ! documentsActionSheet.visible)
    {
        documentsActionSheet = [[UIActionSheet alloc] initWithTitle:nil
                                                           delegate:self
                                                  cancelButtonTitle:nil
                                             destructiveButtonTitle:nil
                                                  otherButtonTitles:@"Load Map", @"Save Map", nil];
        
        [documentsActionSheet showFromBarButtonItem:sender animated:YES];
    }

    else
        [documentsActionSheet dismissWithClickedButtonIndex:-1 animated:YES];
}

- (void)openKMLFile:(NSURL *)fileURL
{
    NSError *error = nil;
    
    SimpleKML *newKML = [SimpleKML KMLWithContentsOfURL:fileURL error:&error];

    if (error)
        [self dataLayerHandler:self didFailToHandleDataLayerAtPath:[fileURL relativePath]];

    else if (newKML)
    {
        NSString *source      = [fileURL relativePath];
        NSString *filename    = [[fileURL relativePath] lastPathComponent];
        NSString *destination = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPathString], filename];
        
        [[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:NULL];
        
        [self layerImportAlertWithName:[fileURL lastPathComponent]];
    }
}

- (void)openRSSFile:(NSURL *)fileURL
{
    NSArray *feedItems = [DSMapBoxFeedParser itemsForFeed:[NSString stringWithContentsOfURL:fileURL
                                                                                   encoding:NSUTF8StringEncoding
                                                                                      error:NULL]];
    
    if ([feedItems count])
    {
        NSString *source      = [fileURL relativePath];
        NSString *filename    = [[fileURL relativePath] lastPathComponent];
        NSString *destination = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPathString], filename];
        
        [[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:NULL];
        
        [self layerImportAlertWithName:[fileURL lastPathComponent]];
    }
    
    else
        [self dataLayerHandler:self didFailToHandleDataLayerAtPath:[fileURL absoluteString]];
}

- (void)openMBTilesFile:(NSURL *)fileURL
{
    NSString *source      = [fileURL relativePath];
    NSString *filename    = [[fileURL relativePath] lastPathComponent];
    NSString *destination = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPathString], filename];
    
    [[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:NULL];
    
    [self layerImportAlertWithName:[fileURL lastPathComponent]];
}

- (IBAction)tappedLayersButton:(id)sender
{
    if (documentsActionSheet)
        [documentsActionSheet dismissWithClickedButtonIndex:-1 animated:NO];
    
    if (layersPopover.popoverVisible)
        [layersPopover dismissPopoverAnimated:YES];
    
    else
    {
        if ( ! layersPopover)
        {
            DSMapBoxLayerController *layerController = [[[DSMapBoxLayerController alloc] initWithNibName:nil bundle:nil] autorelease];
            
            layerController.layerManager = layerManager;
            layerController.delegate     = self;
            
            UINavigationController *wrapper = [[[UINavigationController alloc] initWithRootViewController:layerController] autorelease];
            
            layersPopover = [[UIPopoverController alloc] initWithContentViewController:wrapper];
            
            layersPopover.passthroughViews = nil;
        }
        
        [layersPopover presentPopoverFromBarButtonItem:layersButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    }
}

- (IBAction)tappedClusteringButton:(id)sender
{
    DSMapBoxMarkerManager *markerManager = (DSMapBoxMarkerManager *)[mapView topMostMapView].contents.markerManager;
    
    markerManager.clusteringEnabled = ! markerManager.clusteringEnabled;
    
    if (markerManager.clusteringEnabled)
        clusteringButton.title = @"Turn Clustering Off";
    
    else
        clusteringButton.title = @"Turn Clustering On";
}

- (IBAction)tappedHelpButton:(id)sender
{
    if (layersPopover && layersPopover.popoverVisible)
        [layersPopover dismissPopoverAnimated:NO];
    
    if (documentsActionSheet)
        [documentsActionSheet dismissWithClickedButtonIndex:-1 animated:NO];    
    
    DSMapBoxHelpController *helpController = [[[DSMapBoxHelpController alloc] initWithNibName:nil bundle:nil] autorelease];
    
    UINavigationController *wrapper = [[[UINavigationController alloc] initWithRootViewController:helpController] autorelease];
    
    if ( ! [[NSUserDefaults standardUserDefaults] objectForKey:@"firstRunVideoPlayed"])
    {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"firstRunVideoPlayed"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    helpController.navigationItem.title = @"MapBox Help";
    helpController.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Done"
                                                                                         style:UIBarButtonItemStyleDone
                                                                                        target:helpController
                                                                                        action:@selector(tappedHelpDoneButton:)] autorelease];
    
    wrapper.modalPresentationStyle = UIModalPresentationFormSheet;
    
    [self presentModalViewController:wrapper animated:YES];
}

#pragma mark -

- (void)tileSetDidChange:(NSNotification *)notification
{
    // hide layers popover
    //
    [layersPopover dismissPopoverAnimated:NO];
    
    // determine if we should animate
    //
    BOOL animated = [[notification object] boolValue];

    UIImageView *snapshotView = nil;
    
    // replace map with image to animate away
    //
    if (animated)
    {
        // get an image of the current map
        //
        UIImage *snapshot = [self mapSnapshot];
        
        // swap map view with image view
        //
        snapshotView = [[[UIImageView alloc] initWithFrame:mapView.frame] autorelease];
        snapshotView.image = snapshot;
        [self.view insertSubview:snapshotView atIndex:0];
        [mapView removeFromSuperview];
    }
    
    // force switch to new tile source to update tiles
    //
    NSURL *newTileSetURL = [[DSMapBoxTileSetManager defaultManager] activeTileSetURL];
    
    if ([newTileSetURL isEqual:kDSOpenStreetMapURL])
    {
        id <RMTileSource>source = [[[RMOpenStreetMapSource alloc] init] autorelease];
        
        if (mapView.contents.zoom < [source minZoom])
            mapView.contents.zoom = [source minZoom];
        
        else if (mapView.contents.zoom > [source maxZoom])
            mapView.contents.zoom = [source maxZoom];
        
        mapView.contents.tileSource = source;
        mapView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"loading.png"]];
    }
    else
    {
        id source;
        
        if ([newTileSetURL isTileStreamURL])
            source = [[[RMTileStreamSource alloc] initWithReferenceURL:newTileSetURL] autorelease];
        
        else
            source = [[[RMMBTilesTileSource alloc] initWithTileSetURL:newTileSetURL] autorelease];
        
        mapView.contents.tileSource = source;
        mapView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"loading.png"]];

        // switch to new base layer bounds if less than whole world
        //
        if ( ! [source coversFullWorld] && 
            [source latitudeLongitudeBoundingBox].southwest.latitude >= kLowerLatitudeBounds &&
            [source latitudeLongitudeBoundingBox].northeast.latitude <= kUpperLatitudeBounds)
        {
            RMLatLong sw = [source latitudeLongitudeBoundingBox].southwest;
            RMLatLong ne = [source latitudeLongitudeBoundingBox].northeast;
            
            RMLatLong center = CLLocationCoordinate2DMake((ne.latitude + sw.latitude) / 2, (ne.longitude + sw.longitude) / 2);
            
            mapView.contents.mapCenter = center;
            mapView.contents.zoom      = fmaxf([source minZoomNative], kLowerZoomBounds);
        }
    }

    // perform image to map animated swap back
    //
    if (animated)
    {
        // start up page turn sound effect
        //
        NSURL *soundURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"page_flip" ofType:@"wav"]];
        SystemSoundID sound;
        AudioServicesCreateSystemSoundID((CFURLRef)soundURL, &sound);
        AudioServicesAddSystemSoundCompletion(sound, NULL, NULL, MapBoxMainViewController_SoundCompletionProc, self);
        AudioServicesPlaySystemSound(sound);
        
        // animate swap from old snapshot to new map
        //
        [UIView beginAnimations:nil context:nil];
        [UIView setAnimationTransition:UIViewAnimationTransitionCurlUp forView:self.view cache:YES];
        [UIView setAnimationDuration:0.8];
        [snapshotView removeFromSuperview];
        [self.view insertSubview:mapView atIndex:0];
        [UIView commitAnimations];
    }
    
    // update attribution
    //
    if ([[DSMapBoxTileSetManager defaultManager] activeTileSetAttribution])
    {
        attributionLabel.text   = [[DSMapBoxTileSetManager defaultManager] activeTileSetAttribution];
        attributionLabel.hidden = NO;
    }
    else
    {        
        attributionLabel.hidden = YES;
    }
}

void MapBoxMainViewController_SoundCompletionProc (SystemSoundID sound, void *clientData)
{
    AudioServicesDisposeSystemSoundID(sound);
}

- (void)reachabilityDidChange:(NSNotification *)notification
{
    NSURL *activeTileSetURL = [[DSMapBoxTileSetManager defaultManager] activeTileSetURL];
    
    if (([activeTileSetURL isEqual:kDSOpenStreetMapURL] || [activeTileSetURL isTileStreamURL]) && 
        [(Reachability *)[notification object] currentReachabilityStatus] == NotReachable)
        [self offlineAlert];
}

- (void)offlineAlert
{
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Now Offline"
                                                     message:[NSString stringWithFormat:@"You are now offline. %@ requires an active internet connection, so %@ was activated instead.", [[DSMapBoxTileSetManager defaultManager] activeTileSetURL], [[DSMapBoxTileSetManager defaultManager] defaultTileSetName]]
                                                    delegate:nil
                                           cancelButtonTitle:nil
                                           otherButtonTitles:@"OK", nil] autorelease];

    [[DSMapBoxTileSetManager defaultManager] makeTileSetWithNameActive:[[DSMapBoxTileSetManager defaultManager] defaultTileSetName] animated:NO];
    
    [alert performSelector:@selector(show) withObject:nil afterDelay:0.0];
}

- (UIImage *)mapSnapshot
{
    // zoom to even zoom level to avoid artifacts
    //
    CGFloat oldZoom = mapView.contents.zoom;
    CGPoint center  = CGPointMake(mapView.frame.size.width / 2, mapView.frame.size.height / 2);
    
    if ((CGFloat)ceil(oldZoom) - oldZoom < 0.5)    
        [mapView.contents zoomInToNextNativeZoomAt:center];
    
    else
        [mapView.contents zoomOutToNextNativeZoomAt:center];
    
    // get full screen snapshot
    //
    UIGraphicsBeginImageContext(self.view.bounds.size);
    [self.view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *full = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    // restore previous zoom
    //
    float factor = exp2f(oldZoom - [mapView.contents zoom]);
    [mapView.contents zoomByFactor:factor near:center];
    
    // crop out top toolbar
    //
    CGImageRef cropped = CGImageCreateWithImageInRect(full.CGImage, CGRectMake(0, 
                                                                               toolbar.frame.size.height, 
                                                                               full.size.width, 
                                                                               full.size.height - toolbar.frame.size.height));
    
    // convert & clean up
    //
    UIImage *snapshot = [UIImage imageWithCGImage:cropped];
    CGImageRelease(cropped);

    return snapshot;
}

- (void)zoomBoundsReached:(NSNotification *)notification
{
    if ( ! [[NSUserDefaults standardUserDefaults] boolForKey:@"skipWarningAboutZoom"])
    {
        if ([[NSDate date] timeIntervalSinceDate:self.lastLayerAlertDate] > 5.0)
        {
            NSString *message = [NSString stringWithFormat:@"All layers have built-in zoom limits. MapBox lets you continue to zoom, but layers that don't support the current zoom level won't always appear reliably. %@ is now out of range.", [[notification object] valueForKeyPath:@"tileSource.shortName"]];
            
            UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Layer Zoom Exceeded"
                                                             message:message 
                                                            delegate:self
                                                   cancelButtonTitle:@"Don't Warn"
                                                   otherButtonTitles:@"OK", nil] autorelease];
            
            alert.context = @"zoom warning";
            
            [alert performSelector:@selector(show) withObject:nil afterDelay:0.5];
        }
    }
}

- (void)layerImportAlertWithName:(NSString *)name
{
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Layer Imported"
                                                     message:[NSString stringWithFormat:@"The new layer %@ was imported successfully. You may now find it in the layers menu.", name]
                                                    delegate:nil
                                           cancelButtonTitle:nil
                                           otherButtonTitles:@"OK", nil] autorelease];
    
    [alert show];
}

- (void)layersAdded:(NSNotification *)notification
{
    NSArray *layers = [[notification userInfo] objectForKey:@"selectedLayers"];
    
    NSMutableString *message = [NSMutableString string];
    
    for (NSDictionary *layer in layers)
    {
        [message appendString:[layer objectForKey:@"name"]];
        [message appendString:@"\n"];
        
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [layer objectForKey:@"apiScheme"], @"apiScheme",
                                 [layer objectForKey:@"apiHostname"], @"apiHostname",
                                 [layer objectForKey:@"apiPort"], @"apiPort",
                                 [layer objectForKey:@"apiPath"], @"apiPath",
                                 [layer objectForKey:@"id"], @"id",
                                 ([layer objectForKey:@"bounds"] ? [[layer objectForKey:@"bounds"] componentsJoinedByString:@","] : @""), @"bounds",
                                 ([layer objectForKey:@"center"] ? [[layer objectForKey:@"center"] componentsJoinedByString:@","] : @""), @"center",
                                 ([layer objectForKey:@"name"] ? [layer objectForKey:@"name"] : @""), @"name",
                                 ([layer objectForKey:@"attribution"] ? [layer objectForKey:@"attribution"] : @""), @"attribution",
                                 ([layer objectForKey:@"type"] ? [layer objectForKey:@"type"] : @""), @"type",
                                 ([layer objectForKey:@"version"] ? [layer objectForKey:@"version"] : @""), @"version",
                                 [NSNumber numberWithInt:[[layer objectForKey:@"size"] intValue]], @"size",
                                 [NSNumber numberWithInt:[[layer objectForKey:@"maxzoom"] intValue]], @"maxzoom",
                                 [NSNumber numberWithInt:[[layer objectForKey:@"minzoom"] intValue]], @"minzoom",
                                 ([layer objectForKey:@"description"] ? [layer objectForKey:@"description"] : @""), @"description",
                                 [NSDate dateWithTimeIntervalSince1970:[[layer objectForKey:@"mtime"] intValue]], @"mtime",
                                 ([layer objectForKey:@"basename"] ? [layer objectForKey:@"basename"] : @""), @"basename",
                                 [layer objectForKey:@"tileScheme"], @"tileScheme",
                                 [layer objectForKey:@"tileHostname"], @"tileHostname",
                                 [layer objectForKey:@"tilePort"], @"tilePort",
                                 [layer objectForKey:@"tilePath"], @"tilePath",
                                 nil];
        
        NSString *prefsFolder = [[UIApplication sharedApplication] preferencesFolderPathString];
        
        [dict writeToFile:[NSString stringWithFormat:@"%@/Online Layers/%@.plist", prefsFolder, [layer objectForKey:@"id"]] atomically:YES];
    }
    
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Layers Added"
                                                     message:[NSString stringWithFormat:@"The following layers were added:\n\n%@\n", message] 
                                                    delegate:nil
                                           cancelButtonTitle:nil
                                           otherButtonTitles:@"OK", nil] autorelease];
    
    [alert show];
}

#pragma mark -

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.firstOtherButtonIndex)
    {
        loadController = [[[DSMapBoxDocumentLoadController alloc] initWithNibName:nil bundle:nil] autorelease];

        UINavigationController *wrapper = [[[UINavigationController alloc] initWithRootViewController:loadController] autorelease];
        
        wrapper.navigationBar.barStyle = UIBarStyleBlack;
        
        loadController.navigationItem.leftBarButtonItem  = [[[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                                                             style:UIBarButtonItemStylePlain
                                                                                            target:self
                                                                                            action:@selector(dismissModalViewControllerAnimated:)] autorelease];
        
        loadController.delegate = self;
        
        wrapper.modalPresentationStyle = UIModalPresentationFullScreen;
        wrapper.modalTransitionStyle   = UIModalTransitionStyleFlipHorizontal;

        [self presentModalViewController:wrapper animated:YES];
    }
    else if (buttonIndex > -1)
    {
        saveController = [[[DSMapBoxDocumentSaveController alloc] initWithNibName:nil bundle:nil] autorelease];
        
        saveController.snapshot = [self mapSnapshot];
        
        NSUInteger i = 1;
        
        NSString *docName = nil;
        
        while ( ! docName)
        {
            if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@%@.plist", [DSMapBoxDocumentLoadController saveFolderPath], kDSSaveFileName, (i == 1 ? @"" : [NSString stringWithFormat:@" %i", i])]])
                i++;
            
            else
                docName = [NSString stringWithFormat:@"%@%@", kDSSaveFileName, (i == 1 ? @"" : [NSString stringWithFormat:@" %i", i])];
        }
        
        saveController.name = docName;
        
        UINavigationController *wrapper = [[[UINavigationController alloc] initWithRootViewController:saveController] autorelease];
        
        saveController.navigationItem.leftBarButtonItem  = [[[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                                                             style:UIBarButtonItemStylePlain
                                                                                            target:self
                                                                                            action:@selector(dismissModalViewControllerAnimated:)] autorelease];
        
        saveController.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Save" 
                                                                                             style:UIBarButtonItemStyleDone 
                                                                                            target:self
                                                                                            action:@selector(saveState:)] autorelease];
        
        wrapper.modalPresentationStyle = UIModalPresentationFormSheet;

        [self presentModalViewController:wrapper animated:YES];
    }
}

#pragma mark -

- (void)documentLoadController:(DSMapBoxDocumentLoadController *)controller didLoadDocumentWithName:(NSString *)name
{
    [self restoreState:name];
}

- (void)documentLoadController:(DSMapBoxDocumentLoadController *)controller wantsToSaveDocumentWithName:(NSString *)name
{
    [self saveState:name];
}

#pragma mark -

- (void)dataLayerHandler:(id)handler didFailToHandleDataLayerAtPath:(NSString *)path
{
    self.badParsePath = path;
    
    NSString *message = [NSString stringWithFormat:@"%@ was unable to handle the layer file. Please contact us with a copy of the file in order to request support for it.", [[NSProcessInfo processInfo] processName]];
    
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Layer Problem"
                                                     message:message
                                                    delegate:self
                                           cancelButtonTitle:@"Don't Send"
                                           otherButtonTitles:@"Send Mail", nil] autorelease];
    
    alert.context = @"layer problem";
    
    [alert show];
}

#pragma mark -

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView.context && [alertView.context isEqualToString:@"layer problem"])
    {
        if (buttonIndex == alertView.firstOtherButtonIndex)
        {
            if ([MFMailComposeViewController canSendMail])
            {
                MFMailComposeViewController *mailer = [[[MFMailComposeViewController alloc] init] autorelease];
                
                mailer.mailComposeDelegate = self;
                
                [mailer setToRecipients:[NSArray arrayWithObject:KSupportEmail]];
                [mailer setMessageBody:@"<em>Please provide any additional details about this file or about the error you encountered here.</em>" isHTML:YES];
                
                if ([self.badParsePath hasSuffix:@".kml"])
                {
                    [mailer setSubject:@"Problem KML file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfFile:self.badParsePath]                       
                                     mimeType:@"application/vnd.google-earth.kml+xml" 
                                     fileName:[self.badParsePath lastPathComponent]];
                }
                else if ([self.badParsePath hasSuffix:@".kmz"])
                {
                    [mailer setSubject:@"Problem KMZ file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfFile:self.badParsePath]                       
                                     mimeType:@"application/vnd.google-earth.kmz" 
                                     fileName:[self.badParsePath lastPathComponent]];
                }
                else if ([self.badParsePath hasSuffix:@".rss"] || [self.badParsePath hasSuffix:@".xml"])
                {
                    [mailer setSubject:@"Problem RSS file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfFile:self.badParsePath]                       
                                     mimeType:@"application/rss+xml" 
                                     fileName:[self.badParsePath lastPathComponent]];
                }
                
                mailer.modalPresentationStyle = UIModalPresentationPageSheet;
                
                [self presentModalViewController:mailer animated:YES];
            }
            else
            {
                UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Mail Not Setup"
                                                                 message:@"Please setup Mail first."
                                                                delegate:nil
                                                       cancelButtonTitle:nil
                                                       otherButtonTitles:@"OK", nil] autorelease];
                
                [alert show];
            }
        }
    }
    else if (alertView.context && [alertView.context isEqualToString:@"zoom warning"])
    {
        self.lastLayerAlertDate = [NSDate date];
        
        if (buttonIndex == alertView.cancelButtonIndex)
        {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"skipWarningAboutZoom"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
}

#pragma mark -

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
    switch (result)
    {
        case MFMailComposeResultFailed:
            
            [self dismissModalViewControllerAnimated:NO];
            
            UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Mail Failed"
                                                             message:@"There was a problem sending the mail."
                                                            delegate:nil
                                                   cancelButtonTitle:nil
                                                   otherButtonTitles:@"OK", nil] autorelease];
            
            [alert show];
            
            break;
            
        default:
            
            [self dismissModalViewControllerAnimated:YES];
    }
}

#pragma mark -

- (void)zoomToLayer:(NSDictionary *)layer
{
    NSURL *layerURL = [layer objectForKey:@"URL"];
    
    id source;
    
    if ([layerURL isMBTilesURL])
        source = [[[RMMBTilesTileSource alloc] initWithTileSetURL:layerURL] autorelease];

    else if ([layerURL isTileStreamURL])
        source = [[[RMTileStreamSource alloc] initWithReferenceURL:layerURL] autorelease];
    
    if ( ! source)
        return;
    
    mapView.contents.zoom = ([source minZoomNative] >= kLowerZoomBounds ? [source minZoomNative] : kLowerZoomBounds);
    
    if ( ! [source coversFullWorld])
    {
        RMSphericalTrapezium bbox = [source latitudeLongitudeBoundingBox];
        
        CLLocationDegrees lon, lat;
        
        lon = (bbox.northeast.longitude + bbox.southwest.longitude) / 2;
        lat = (bbox.northeast.latitude  + bbox.southwest.latitude)  / 2;
        
        [mapView.contents moveToLatLong:CLLocationCoordinate2DMake(lat, lon)];
    }
}

- (void)presentAddLayerHelper
{
    if ([reachability currentReachabilityStatus] == NotReachable)
    {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"No Internet Connection"
                                                         message:@"Adding a layer requires an active internet connection."
                                                        delegate:nil
                                               cancelButtonTitle:nil
                                               otherButtonTitles:@"OK", nil] autorelease];
        
        [alert show];
        
        return;
    }
    
    // dismiss layer UI
    //
    [self tappedLayersButton:self];
    
    DSMapBoxLayerAddNavigationController *layerAddController = [[[DSMapBoxLayerAddNavigationController alloc] initWithNibName:nil bundle:nil] autorelease];
    
    layerAddController.modalPresentationStyle = UIModalPresentationFormSheet;
    layerAddController.modalTransitionStyle   = UIModalTransitionStyleCoverVertical;
    
    [self presentModalViewController:layerAddController animated:YES];
}

@end