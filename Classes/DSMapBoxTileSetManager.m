//
//  DSMapBoxTileSetManager.m
//  MapBoxiPadDemo
//
//  Created by Justin R. Miller on 6/22/10.
//  Copyright 2010 Code Sorcery Workshop. All rights reserved.
//

#import "DSMapBoxTileSetManager.h"
#import "UIApplication_Additions.h"
#import "FMDatabase.h"

@interface DSMapBoxTileSetManager (DSMapBoxTileSetManagerPrivate)

- (NSMutableDictionary *)downloadForConnection:(NSURLConnection *)connection;

@end

#pragma mark -

@implementation DSMapBoxTileSetManager

static DSMapBoxTileSetManager *defaultManager;

+ (DSMapBoxTileSetManager *)defaultManager
{
    @synchronized(@"DSMapBoxTileSetManager")
    {
        if ( ! defaultManager)
            defaultManager = [[self alloc] init];
    }
    
    return defaultManager;
}

- (id)init
{
    self = [super init];
    
    if (self != nil)
    {
        NSArray *bundledTileSets = [[NSBundle mainBundle] pathsForResourcesOfType:@"mbtiles" inDirectory:nil];
        
        NSAssert([bundledTileSets count] > 0, @"No bundled tile sets found in application");
        
        NSString *path = [[bundledTileSets sortedArrayUsingSelector:@selector(compare:)] objectAtIndex:0];
        
        _activeTileSetURL  = [[NSURL fileURLWithPath:path] retain];
        _defaultTileSetURL = [_activeTileSetURL copy];
        _activeDownloads   = [[NSMutableArray array] retain];
    }
    
    return self;
}

- (void)dealloc
{
    [_activeTileSetURL  release];
    [_defaultTileSetURL release];
    [_activeDownloads   release];
    
    [super dealloc];
}

#pragma mark -

- (NSArray *)alternateTileSetPathsOfType:(DSMapBoxTileSetType)tileSetType
{
    NSArray *docsContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[UIApplication sharedApplication] documentsFolderPathString] error:NULL];
    
    NSArray *alternateFileNames = [docsContents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF ENDSWITH '.mbtiles'"]];

    NSMutableArray *paths = [NSMutableArray array];
    
    for (NSString *alternateFileName in alternateFileNames)
    {
        NSString *path = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPathString], alternateFileName];
        
        FMDatabase *db = [FMDatabase databaseWithPath:path];

        if ( ! [db open])
            continue;
        
        FMResultSet *results = [db executeQuery:@"select value from metadata where name = 'type'"];
        
        if ([db hadError] && [db close])
            continue;
        
        [results next];
        
        if (tileSetType == DSMapBoxTileSetTypeBaselayer && [[results stringForColumn:@"value"] isEqualToString:@"baselayer"])
            [paths addObject:[NSURL fileURLWithPath:path]];
        
        else if (tileSetType == DSMapBoxTileSetTypeOverlay && [[results stringForColumn:@"value"] isEqualToString:@"overlay"])
            [paths addObject:[NSURL fileURLWithPath:path]];
        
        [results close];
        
        [db close];
    }

    return [NSArray arrayWithArray:paths];
}

- (NSString *)displayNameForTileSetAtURL:(NSURL *)tileSetURL
{
    NSString *defaultName = [[tileSetURL relativePath] lastPathComponent];
    
    FMDatabase *db = [FMDatabase databaseWithPath:[tileSetURL relativePath]];
    
    if ( ! [db open])
        return defaultName;
    
    FMResultSet *nameResults = [db executeQuery:@"select value from metadata where name = 'name'"];
    
    if ([db hadError] && [db close])
        return defaultName;
    
    [nameResults next];
    
    NSString *displayName = [nameResults stringForColumn:@"value"];
    
    [nameResults close];
    
    FMResultSet *versionResults = [db executeQuery:@"select value from metadata where name = 'version'"];
    
    if ([db hadError] && [db close])
        return defaultName;
    
    [versionResults next];
    
    NSString *version = [versionResults stringForColumn:@"value"];
    
    [versionResults close];

    [db close];
    
    if ([version isEqualToString:@"1.0"])
        return displayName;
    
    else
        return [NSString stringWithFormat:@"%@ (%@)", displayName, version];
    
    return defaultName;
}

- (NSString *)descriptionForTileSetAtURL:(NSURL *)tileSetURL
{
    NSString *defaultDescription = @"";
    
    FMDatabase *db = [FMDatabase databaseWithPath:[tileSetURL relativePath]];
    
    if ( ! [db open])
        return defaultDescription;
    
    FMResultSet *descriptionResults = [db executeQuery:@"select value from metadata where name = 'description'"];
    
    if ([db hadError] && [db close])
        return defaultDescription;
    
    [descriptionResults next];
    
    NSString *description = [descriptionResults stringForColumn:@"value"];
    
    [descriptionResults close];
    
    [db close];
    
    return description;
}

- (NSMutableDictionary *)downloadForConnection:(NSURLConnection *)connection
{
    for (NSMutableDictionary *download in _activeDownloads)
        if ([[download objectForKey:@"connection"] isEqual:connection])
            return download;
    
    return nil;
}

#pragma mark -

- (BOOL)isUsingDefaultTileSet
{
    return [_activeTileSetURL isEqual:_defaultTileSetURL];
}

- (NSString *)defaultTileSetName
{
    return [self displayNameForTileSetAtURL:_defaultTileSetURL];
}

- (BOOL)importTileSetFromURL:(NSURL *)importURL
{
    for (NSMutableDictionary *download in _activeDownloads)
        if ([[download objectForKey:@"url"] isEqualToString:[importURL absoluteString]])
            return NO;
    
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:[NSURLRequest requestWithURL:importURL] delegate:self startImmediately:NO];
    
    NSMutableDictionary *newDownload = [NSMutableDictionary dictionaryWithObjectsAndKeys:connection,                                  @"connection", 
                                                                                         [importURL absoluteString],                  @"url", 
                                                                                         [self displayNameForTileSetAtURL:importURL], @"name", 
                                                                                         [NSNumber numberWithFloat:0],                @"completion", 
                                                                                         nil];

    [_activeDownloads addObject:newDownload];
    
    NSString *baseName = [[[importURL relativePath] componentsSeparatedByString:@"/"] lastObject];
    
    [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPathString], baseName] error:NULL];
    
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:[[NSRunLoop currentRunLoop] currentMode]];
    [connection start];
    
    return YES;
}

- (BOOL)deleteTileSetWithName:(NSString *)tileSetName
{
    return NO;
}

- (NSURL *)activeTileSetURL
{
    return _activeTileSetURL;
}

- (NSString *)activeTileSetName
{
    return [self displayNameForTileSetAtURL:_activeTileSetURL];
}

- (NSArray *)activeDownloads
{
    return _activeDownloads;
}

- (BOOL)makeTileSetWithNameActive:(NSString *)tileSetName
{
    NSLog(@"activating %@", tileSetName);
    
    NSURL *currentPath = [[_activeTileSetURL copy] autorelease];
    
    if ([tileSetName isEqualToString:[self displayNameForTileSetAtURL:_defaultTileSetURL]])
    {
        if ( ! [currentPath isEqual:_defaultTileSetURL])
        {
            [_activeTileSetURL release];
            _activeTileSetURL = [_defaultTileSetURL copy];
        }
    }
    else
    {
        for (NSURL *alternatePath in [self alternateTileSetPaths])
        {
            if ([[self displayNameForTileSetAtURL:alternatePath] isEqualToString:tileSetName])
            {
                [_activeTileSetURL release];
                _activeTileSetURL = [alternatePath copy];
                
                break;
            }
        }
    }
    
    return ! [currentPath isEqual:_activeTileSetURL];
}

#pragma mark -

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSDictionary *download = [self downloadForConnection:connection];

    NSLog(@"download error for %@: %@", download, error);
    
    [connection cancel];
    
    NSString *baseName = [[[download objectForKey:@"url"] componentsSeparatedByString:@"/"] lastObject];
    
    NSString *inProgress = [NSString stringWithFormat:@"%@/%@.mbdownload", [[UIApplication sharedApplication] documentsFolderPathString], baseName];
    
    [[NSFileManager defaultManager] removeItemAtPath:inProgress error:NULL];
    
    [_activeDownloads removeObject:download];
    
    [connection release];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSMutableDictionary *download = [self downloadForConnection:connection];

    NSLog(@"received response for %@: %@", download, [(NSHTTPURLResponse *)response allHeaderFields]);
    
    NSString *baseName = [[[download objectForKey:@"url"] componentsSeparatedByString:@"/"] lastObject];
    
    [[NSFileManager defaultManager] createFileAtPath:[NSString stringWithFormat:@"%@/%@.mbdownload", [[UIApplication sharedApplication] documentsFolderPathString], baseName]
                                            contents:[NSData data]
                                          attributes:nil];
    
    if ([[(NSHTTPURLResponse *)response allHeaderFields] objectForKey:@"Content-Length"])
        [download setObject:[NSNumber numberWithFloat:[[[(NSHTTPURLResponse *)response allHeaderFields] objectForKey:@"Content-Length"] floatValue]]
                     forKey:@"size"];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    NSMutableDictionary *download = [self downloadForConnection:connection];

    NSLog(@"received %i bytes for %@", [data length], download);
    
    [download setObject:[NSNumber numberWithFloat:([[download objectForKey:@"completion"] floatValue] + (float)[data length])] forKey:@"completion"];
    
    NSString *baseName = [[[download objectForKey:@"url"] componentsSeparatedByString:@"/"] lastObject];

    NSString *inProgress = [NSString stringWithFormat:@"%@/%@.mbdownload", [[UIApplication sharedApplication] documentsFolderPathString], baseName];
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:inProgress];
    
    [fileHandle seekToEndOfFile];
    
    [fileHandle writeData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSDictionary *download = [self downloadForConnection:connection];

    NSLog(@"finished loading for %@", download);
    
    NSString *baseName = [[[download objectForKey:@"url"] componentsSeparatedByString:@"/"] lastObject];
    
    NSString *inProgress = [NSString stringWithFormat:@"%@/%@.mbdownload", [[UIApplication sharedApplication] documentsFolderPathString], baseName];
    
    [[NSFileManager defaultManager] moveItemAtPath:inProgress 
                                            toPath:[NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPathString], baseName] 
                                             error:NULL];
    
    [_activeDownloads removeObject:download];

    [connection release];
}

@end