#import "YapCollectionsDatabase.h"
#import "YapCollectionsDatabasePrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapCollectionKey.h"
#import "YapDatabaseLogging.h"

#import "sqlite3.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif

NSString *const YapCollectionsDatabaseObjectChangesKey      = @"objectChanges";
NSString *const YapCollectionsDatabaseMetadataChangesKey    = @"metadataChanges";
NSString *const YapCollectionsDatabaseRemovedKeysKey        = @"removedKeys";
NSString *const YapCollectionsDatabaseRemovedCollectionsKey = @"removedCollections";
NSString *const YapCollectionsDatabaseAllKeysRemovedKey     = @"allKeysRemoved";

/**
 * YapDatabase provides concurrent thread-safe access to a key-value database backed by sqlite.
 *
 * A vast majority of the implementation is in YapAbstractDatabase.
 * The YapAbstractDatabase implementation is shared between YapDatabase and YapCollectionsDatabase.
**/
@implementation YapCollectionsDatabase

/**
 * Required override method from YapAbstractDatabase.
 *
 * The abstract version creates the 'yap' table, which is used internally.
 * Our version creates the 'database' table, which holds the key/object/metadata rows.
**/
- (BOOL)createTables
{
	int status;
	
	char *createDatabaseStatement =
	    "CREATE TABLE IF NOT EXISTS \"database2\""
	    " (\"rowid\" INTEGER PRIMARY KEY,"
	    "  \"collection\" CHAR NOT NULL,"
	    "  \"key\" CHAR NOT NULL,"
	    "  \"data\" BLOB,"
	    "  \"metadata\" BLOB"
	    " );";
	
	status = sqlite3_exec(db, createDatabaseStatement, NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed creating 'database' table: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	char *createIndexStatement =
	    "CREATE UNIQUE INDEX IF NOT EXISTS \"true_primary_key\" ON \"database2\" ( \"collection\", \"key\" );";
	
	status = sqlite3_exec(db, createIndexStatement, NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		NSLog(@"Failed creating index on 'database' table: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	return [super createTables];
}

/**
 * Required override method from YapAbstractDatabase.
 * 
 * This method is used when creating the YapSharedCache, and provides the type of key's we'll be using for the cache.
**/
- (Class)cacheKeyClass
{
	return [YapCollectionKey class];
}

/**
 * In version 3 (more commonly known as version 2.1),
 * we altered the tables to use INTEGER PRIMARY KEY's so we could pass rowid's to extensions.
 * 
 * This method migrates 'database' to 'database2'.
**/
- (BOOL)upgradeTable_2_3
{
	int status;
	
	char *stmt = "INSERT INTO \"database2\" (\"collection\", \"key\", \"data\", \"metadata\")"
	             " SELECT \"collection\", \"key\", \"data\", \"metadata\" FROM \"database\";";
	
	status = sqlite3_exec(db, stmt, NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error migrating 'database' to 'database2': %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_exec(db, "DROP TABLE IF EXISTS \"database\"", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed dropping 'database' table: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	return YES;
}

/**
 * This is a public method called to create a new connection.
 *
 * All the details of managing connections, and managing connection state, is handled by YapAbstractDatabase.
**/
- (YapCollectionsDatabaseConnection *)newConnection
{
	YapCollectionsDatabaseConnection *connection = [[YapCollectionsDatabaseConnection alloc] initWithDatabase:self];
	
	[self addConnection:connection];
	return connection;
}

@end
