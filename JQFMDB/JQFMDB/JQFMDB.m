//
//  JQFMDB.m
//
//  Created by Joker on 17/3/7.
//  GitHub: https://github.com/gaojunquan/JQFMDB
//

#import "JQFMDB.h"
#import <objc/runtime.h>

// 数据库中常见的几种类型
#define SQL_TEXT     @"TEXT" //文本
#define SQL_INTEGER  @"INTEGER" //int long integer ...
#define SQL_REAL     @"REAL" //浮点
#define SQL_BLOB     @"BLOB" //data

static NSString *_dbName;
static FMDatabaseQueue *_dbQueue;
static FMDatabase *_db;

@implementation JQFMDB

- (FMDatabaseQueue *)dbQueue
{
    if (!_dbQueue) {
        NSString *path = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:_dbName];
        FMDatabaseQueue *fmdb = [FMDatabaseQueue databaseQueueWithPath:path];
        _dbQueue = fmdb;
        [_db close];
        _db = [fmdb valueForKey:@"_db"];
    }
    return _dbQueue;
}

static JQFMDB *jqdb = nil;
+ (instancetype)shareDatabase
{
    if (!jqdb) {
        [JQFMDB shareDatabase:nil];
    }
    return jqdb;
}

+ (instancetype)shareDatabase:(NSString *)dbName
{
    return [JQFMDB shareDatabase:dbName path:nil];
}

+ (instancetype)shareDatabase:(NSString *)dbName path:(NSString *)dbPath
{
    if (!jqdb) {
        
        NSString *path;
        if (!dbName) {
            dbName = @"JQFMDB.sqlite";
        }
        if (!dbPath) {
            path = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:dbName];
        } else {
            path = dbPath;
        }
        
        FMDatabase *fmdb = [FMDatabase databaseWithPath:path];
        if ([fmdb open]) {
            jqdb = JQFMDB.new;
            _db = fmdb;
            _dbName = dbName;
        }
    }
    return jqdb;
}

- (instancetype)initWithDBName:(NSString *)dbName
{
    return [self initWithDBName:dbName path:nil];
}

- (instancetype)initWithDBName:(NSString *)dbName path:(NSString *)dbPath
{
    if (!dbName) {
        dbName = @"JQFMDB.sqlite";
    }
    NSString *path;
    if (!dbPath) {
        path = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:dbName];
    } else {
        path = dbPath;
    }
    
    FMDatabase *fmdb = [FMDatabase databaseWithPath:path];
    
    if ([fmdb open]) {
        self = [self init];
        if (self) {
            _db = fmdb;
            _dbName = dbName;
            return self;
        }
    }
    return nil;
}

- (BOOL)jq_createTable:(NSString *)tableName dicOrModel:(id)parameters
{
    return [self jq_createTable:tableName dicOrModel:parameters excludeName:nil];
}

- (BOOL)jq_createTable:(NSString *)tableName dicOrModel:(id)parameters excludeName:(NSArray *)nameArr
{
    NSString *sqlStr;
    if ([parameters isKindOfClass:[NSDictionary class]]) {
        sqlStr = [self createTable:tableName dictionary:parameters excludeName:nameArr];
    } else {
        Class CLS;
        if ([parameters isKindOfClass:[NSString class]]) {
            if (!NSClassFromString(parameters)) {
                CLS = nil;
            } else {
                CLS = NSClassFromString(parameters);
            }
        } else if ([parameters isKindOfClass:[NSObject class]]) {
            CLS = [parameters class];
        } else {
            CLS = parameters;
        }
        sqlStr = [self createTable:tableName model:CLS excludeName:nameArr];
    }
    BOOL creatFlag;
    creatFlag = [_db executeUpdate:sqlStr];
    
    return creatFlag;
}

- (NSString *)createTable:(NSString *)tableName dictionary:(NSDictionary *)dic excludeName:(NSArray *)nameArr
{
    NSMutableString *fieldStr = [[NSMutableString alloc] initWithFormat:@"CREATE TABLE %@ (", tableName];
    
    int keyCount = 0;
    for (NSString *key in dic) {
        
        keyCount++;
        if (nameArr && [nameArr containsObject:key]) {
            continue;
        }
        if (keyCount == dic.count) {
            [fieldStr appendFormat:@" %@ %@)", key, dic[key]];
            break;
        }
        
        [fieldStr appendFormat:@" %@ %@,", key, dic[key]];
    }
    
    return fieldStr;
}

- (NSString *)createTable:(NSString *)tableName model:(Class)cls excludeName:(NSArray *)nameArr
{
    NSMutableString *fieldStr = [[NSMutableString alloc] initWithFormat:@"CREATE TABLE %@ (", tableName];
    
    NSDictionary *dic = [self modelToDictionary:cls excludePropertyName:nameArr];
    int keyCount = 0;
    for (NSString *key in dic) {
        
        keyCount++;
        
        if (keyCount == dic.count) {
            [fieldStr appendFormat:@" %@ %@)", key, dic[key]];
            break;
        }
        
        [fieldStr appendFormat:@" %@ %@,", key, dic[key]];
    }
    
    return fieldStr;
}

#pragma mark - *************** runtime获取属性名和类型
- (NSDictionary *)modelToDictionary:(Class)cls excludePropertyName:(NSArray *)nameArr
{
    NSMutableDictionary *mDic = [NSMutableDictionary dictionaryWithCapacity:0];
    unsigned int outCount;
    objc_property_t *properties = class_copyPropertyList(cls, &outCount);
    for (int i = 0; i < outCount; i++) {
        
        NSString *name = [NSString stringWithCString:property_getName(properties[i]) encoding:NSUTF8StringEncoding];
        if ([nameArr containsObject:name]) continue;
        
        NSString *type = [NSString stringWithCString:property_getAttributes(properties[i]) encoding:NSUTF8StringEncoding];
        
        id value = [self propertTypeConvert:type];
        if (value) {
            [mDic setObject:value forKey:name];
        }
        
        
    }
    
    return mDic;
}

// 获取model或者dictionary的key和value
- (NSDictionary *)getModelPropertyKeyValue:(id)model tableName:(NSString *)tableName clomnArr:(NSArray *)clomnArr
{
    NSMutableDictionary *mDic = [NSMutableDictionary dictionaryWithCapacity:0];
    unsigned int outCount;
    objc_property_t *properties = class_copyPropertyList([model class], &outCount);
    
    for (int i = 0; i < outCount; i++) {
        
        NSString *name = [NSString stringWithCString:property_getName(properties[i]) encoding:NSUTF8StringEncoding];
        if (![clomnArr containsObject:name]) {
            continue;
        }
        
        id value = [model valueForKey:name];
        if (value) {
            [mDic setObject:value forKey:name];
        }
    }
    
    return mDic;
}

- (NSString *)propertTypeConvert:(NSString *)typeStr
{
    NSString *resultStr = nil;
    if ([typeStr hasPrefix:@"T@\"NSString\""]) {
        resultStr = SQL_TEXT;
    } else if ([typeStr hasPrefix:@"T@\"NSData\""]) {
        resultStr = SQL_BLOB;
    } else if ([typeStr hasPrefix:@"Ti"]||[typeStr hasPrefix:@"TI"]||[typeStr hasPrefix:@"Ts"]||[typeStr hasPrefix:@"TS"]||[typeStr hasPrefix:@"T@\"NSNumber\""]||[typeStr hasPrefix:@"TB"]||[typeStr hasPrefix:@"Tq"]||[typeStr hasPrefix:@"TQ"]) {
        resultStr = SQL_INTEGER;
    } else if ([typeStr hasPrefix:@"Tf"] || [typeStr hasPrefix:@"Td"]){
        resultStr= SQL_REAL;
    }
    
    return resultStr;
}

// 得到表里的字段名称
- (NSArray *)getColumnArr:(NSString *)tableName db:(FMDatabase *)db
{
    NSMutableArray *mArr = [NSMutableArray arrayWithCapacity:0];
    
    FMResultSet *resultSet = [db getTableSchema:tableName];
    
    while ([resultSet next]) {
        [mArr addObject:[resultSet stringForColumn:@"name"]];
    }
    
    return mArr;
}

#pragma mark - *************** 增删改查
- (BOOL)jq_insertTable:(NSString *)tableName dicOrModel:(id)parameters
{

    BOOL flag;
    
    NSDictionary *dic;
    NSArray *clomnArr = [self getColumnArr:tableName db:_db];
    if ([parameters isKindOfClass:[NSDictionary class]]) {
        dic = parameters;
    }else {
        dic = [self getModelPropertyKeyValue:parameters tableName:tableName clomnArr:clomnArr];
    }
    
    NSMutableString *finalStr = [[NSMutableString alloc] initWithFormat:@"INSERT INTO %@ (", tableName];
    NSMutableString *tempStr = [NSMutableString stringWithCapacity:0];
    NSMutableArray *argumentsArr = [NSMutableArray arrayWithCapacity:0];
    
    for (NSString *key in dic) {
        
        if (![clomnArr containsObject:key]) {
            continue;
        }
        [finalStr appendFormat:@"%@,", key];
        [tempStr appendString:@"?,"];
        
        [argumentsArr addObject:dic[key]];
    }
    
    [finalStr deleteCharactersInRange:NSMakeRange(finalStr.length-1, 1)];
    if (tempStr.length)
        [tempStr deleteCharactersInRange:NSMakeRange(tempStr.length-1, 1)];
    
    [finalStr appendFormat:@") values (%@)", tempStr];
    
    flag = [_db executeUpdate:finalStr withArgumentsInArray:argumentsArr];
    return flag;
}

- (BOOL)jq_deleteTable:(NSString *)tableName whereFormat:(NSString *)format, ...
{
    BOOL flag;
    NSMutableString *finalStr = [[NSMutableString alloc] initWithFormat:@"delete from %@  %@", tableName,format];
    flag = [_db executeUpdate:finalStr];
    
    return flag;
}

- (BOOL)jq_updateTable:(NSString *)tableName dicOrModel:(id)parameters whereFormat:(NSString *)format, ...
{
    BOOL flag;
    NSDictionary *dic;
    NSArray *clomnArr = [self getColumnArr:tableName db:_db];
    if ([parameters isKindOfClass:[NSDictionary class]]) {
        dic = parameters;
    }else {
        dic = [self getModelPropertyKeyValue:parameters tableName:tableName clomnArr:clomnArr];
    }
    
    NSMutableString *finalStr = [[NSMutableString alloc] initWithFormat:@"update %@ set ", tableName];
    NSMutableArray *argumentsArr = [NSMutableArray arrayWithCapacity:0];
    
    for (NSString *key in dic) {
        
        if (![clomnArr containsObject:key]) {
            continue;
        }
        [finalStr appendFormat:@"%@ = %@,", key, @"?"];
        [argumentsArr addObject:dic[key]];
    }
    
    [finalStr deleteCharactersInRange:NSMakeRange(finalStr.length-1, 1)];
    if (format.length) [finalStr appendFormat:@" %@", format];
    
    
    flag =  [_db executeUpdate:finalStr withArgumentsInArray:argumentsArr];
    
    return flag;
}

- (NSArray *)jq_lookupTable:(NSString *)tableName dicOrModel:(id)parameters whereFormat:(NSString *)format, ...
{
    NSMutableArray *resultMArr = [NSMutableArray arrayWithCapacity:0];
    NSDictionary *dic;
    NSMutableString *finalStr = [[NSMutableString alloc] initWithFormat:@"select * from %@ %@", tableName, format?format:@""];
    NSArray *clomnArr = [self getColumnArr:tableName db:_db];
    
    FMResultSet *set = [_db executeQuery:finalStr];
    
    if ([parameters isKindOfClass:[NSDictionary class]]) {
        dic = parameters;
        
        while ([set next]) {
            
            NSDictionary *resultDic = nil;
            for (NSString *key in dic) {
                resultDic = nil;
                
                if ([dic[key] isEqualToString:SQL_TEXT]) {
                    id value = [set stringForColumn:key];
                    if (value)
                        resultDic = [NSDictionary dictionaryWithObject:value forKey:key];
                } else if ([dic[key] isEqualToString:SQL_INTEGER]) {
                    resultDic = [NSDictionary dictionaryWithObject:@([set longLongIntForColumn:key]) forKey:key];
                } else if ([dic[key] isEqualToString:SQL_REAL]) {
                    resultDic = [NSDictionary dictionaryWithObject:[NSNumber numberWithDouble:[set doubleForColumn:key]] forKey:key];
                } else if ([dic[key] isEqualToString:SQL_BLOB]) {
                    id value = [set dataForColumn:key];
                    if (value)
                        resultDic = [NSDictionary dictionaryWithObject:value forKey:key];
                }
            }
            
            if (resultDic) [resultMArr addObject:resultDic];
        }
        
    }else {
        
        Class CLS;
        if ([parameters isKindOfClass:[NSString class]]) {
            if (!NSClassFromString(parameters)) {
                CLS = nil;
            } else {
                CLS = NSClassFromString(parameters);
            }
        } else if ([parameters isKindOfClass:[NSObject class]]) {
            CLS = [parameters class];
        } else {
            CLS = parameters;
        }
        
        if (CLS) {
            NSDictionary *propertyType = [self modelToDictionary:CLS excludePropertyName:nil];
            
            while ([set next]) {
                
                id model = CLS.new;
                for (NSString *name in clomnArr) {
                    
                    if ([propertyType[name] isEqualToString:SQL_TEXT]) {
                        id value = [set stringForColumn:name];
                        if (value)
                            [model setValue:value forKey:name];
                    } else if ([propertyType[name] isEqualToString:SQL_INTEGER]) {
                        [model setValue:@([set longLongIntForColumn:name]) forKey:name];
                    } else if ([propertyType[name] isEqualToString:SQL_REAL]) {
                        [model setValue:[NSNumber numberWithDouble:[set doubleForColumn:name]] forKey:name];
                    } else if ([propertyType[name] isEqualToString:SQL_BLOB]) {
                        id value = [set dataForColumn:name];
                        if (value)
                            [model setValue:value forKey:name];
                    }
                }
                
                [resultMArr addObject:model];
            }
        }
        
    }
    
    return resultMArr;
}

// 直接传一个array插入
- (NSArray *)jq_insertTable:(NSString *)tableName dicOrModelArray:(NSArray *)dicOrModelArray
{
    int errorIndex = 0;
    NSMutableArray *resultMArr = [NSMutableArray arrayWithCapacity:0];
    NSDictionary *dic;
    NSArray *clomnArr = [self getColumnArr:tableName db:_db];
    for (id parameters in dicOrModelArray) {
        
        if ([parameters isKindOfClass:[NSDictionary class]]) {
            dic = parameters;
        }else {
            dic = [self getModelPropertyKeyValue:parameters tableName:tableName clomnArr:clomnArr];
        }
        
        NSMutableString *finalStr = [[NSMutableString alloc] initWithFormat:@"INSERT INTO %@ (", tableName];
        NSMutableString *tempStr = [NSMutableString stringWithCapacity:0];
        NSMutableArray *argumentsArr = [NSMutableArray arrayWithCapacity:0];
        
        for (NSString *key in dic) {
            
            if (![clomnArr containsObject:key]) {
                continue;
            }
            [finalStr appendFormat:@"%@,", key];
            [tempStr appendString:@"?,"];
            [argumentsArr addObject:dic[key]];
        }
        
        [finalStr deleteCharactersInRange:NSMakeRange(finalStr.length-1, 1)];
        if (tempStr.length)
            [tempStr deleteCharactersInRange:NSMakeRange(tempStr.length-1, 1)];
        
        [finalStr appendFormat:@") values (%@)", tempStr];
        
        if (![_db executeUpdate:finalStr withArgumentsInArray:argumentsArr]) {
            [resultMArr addObject:@(errorIndex)];
        }
        errorIndex++;

    }
    
    return resultMArr;
}

- (BOOL)jq_deleteTable:(NSString *)tableName
{
    NSString *sqlstr = [NSString stringWithFormat:@"DROP TABLE %@", tableName];
    if (![_db executeUpdate:sqlstr])
    {
        return NO;
    }
    return YES;
}

- (BOOL)jq_deleteAllDataFromTable:(NSString *)tableName
{
    NSString *sqlstr = [NSString stringWithFormat:@"DELETE FROM %@", tableName];
    if (![_db executeUpdate:sqlstr])
    {
        return NO;
    }
    
    return YES;
}

- (BOOL)jq_isExistTable:(NSString *)tableName
{
    FMResultSet *set = [_db executeQuery:@"SELECT count(*) as 'count' FROM sqlite_master WHERE type ='table' and name = ?", tableName];
    while ([set next])
    {
        NSInteger count = [set intForColumn:@"count"];
        if (count == 0) {
            return NO;
        } else {
            return YES;
        }
    }
    return NO;
}

- (NSArray *)jq_columnNameArray:(NSString *)tableName
{
    return [self getColumnArr:tableName db:_db];
}

- (int)jq_tableItemCount:(NSString *)tableName
{
    NSString *sqlstr = [NSString stringWithFormat:@"SELECT count(*) as 'count' FROM %@", tableName];
    FMResultSet *set = [_db executeQuery:sqlstr];
    while ([set next])
    {
        return [set intForColumn:@"count"];
    }
    return 0;
}

// =============================   多线程操作    ===============================

- (void)jq_inDatabase:(void(^)(void))block
{
    [[self dbQueue] inDatabase:^(FMDatabase *db) {
        block();
    }];
}

- (void)jq_inTransaction:(void(^)(BOOL *rollback))block
{
    [[self dbQueue] inTransaction:^(FMDatabase *db, BOOL *rollback) {
        block(rollback);
    }];
    
}


@end

