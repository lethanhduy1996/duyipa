// WQFiles Patch Manager: import authenticated .3105 v1-v3, apply with backup,
// restore only when the live file hash matches the applied payload.
// GPL-3.0-or-later.
#import "WQPatch.h"
#import "WQAccess.h"
#import "WQLaunchServices.h"
#import "WQUI.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <stdlib.h>
#import <string.h>

extern char *wq_decode_3105(const uint8_t *, intptr_t, const char *);
extern char *wq_create_3105(const char *, const char *);

static NSString *WQPHash(NSData *d) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, bytes);
    NSMutableString *out = NSMutableString.new;
    for (int i=0; i<CC_SHA256_DIGEST_LENGTH; i++) [out appendFormat:@"%02x", bytes[i]];
    return out;
}
static BOOL WQPValidBundle(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length<3 || s.length>255) return NO;
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$" options:0 error:nil];
    return [re numberOfMatchesInString:s options:0 range:NSMakeRange(0,s.length)]==1;
}
static BOOL WQPValidPath(NSString *s) {
    if (![s isKindOfClass:NSString.class] || !s.length || s.length>1024 || [s hasPrefix:@"/"] ||
        [s containsString:@"\\"] || [s rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) return NO;
    NSArray *parts=[s componentsSeparatedByString:@"/"];
    if (parts.count<2 || ![@[@"Documents",@"Library",@"tmp"] containsObject:parts.firstObject]) return NO;
    for (NSString *part in parts) if (!part.length || [part isEqualToString:@"."] || [part isEqualToString:@".."]) return NO;
    return YES;
}
static NSString *WQPStore(void) {
    NSString *root=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    return [root stringByAppendingPathComponent:@"WQPatchBackups"];
}
static BOOL WQPWrite(NSDictionary *json, NSString *path) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:nil];
}
static NSDictionary *WQPRead(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path];
    id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    return [value isKindOfClass:NSDictionary.class]?value:nil;
}
static NSString *WQPLocate(NSString *bundle) {
    NSString *result=nil;
    for (NSString *folder in wq_ls_container_paths(nil)) {
        NSString *label=wq_bundle_id_for_container(folder) ?: wq_container_label(folder);
        if (![label isEqualToString:bundle]) continue;
        if (result) return nil; // ambiguous identity
        result=folder;
    }
    return result;
}
// Resolve each bundle ID once per transaction. Most packages contain several files
// for the same app: repeatedly scanning LaunchServices for each rule is unnecessary.
// Failed/ambiguous lookups are also cached; never resolve to an arbitrary match.
static NSString *WQPLocateCached(NSString *bundle, NSMutableDictionary<NSString *, id> *cache) {
    if (!bundle.length) return nil;
    id cached=cache[bundle];
    if (cached) return cached == NSNull.null ? nil : (NSString *)cached;
    NSString *found=WQPLocate(bundle);
    cache[bundle]=found ?: NSNull.null;
    return found;
}
// A file picked from WQFiles: derive the exact app data-container root,
// Bundle ID and relative path. No user-entered absolute destination is trusted.
static NSDictionary<NSString *,NSString *> *WQPDescribeAppFile(NSString *filePath, NSString **error) {
    NSString *path=[filePath stringByStandardizingPath];
    if ([path hasPrefix:@"/var/"]) path=[@"/private" stringByAppendingString:path];
    NSArray<NSString *> *prefixes=@[@"/private/var/mobile/Containers/Data/Application/",
                                    @"/private/var/containers/Data/Application/"];
    NSString *root=nil, *relative=nil;
    for (NSString *prefix in prefixes) {
        if (![path hasPrefix:prefix]) continue;
        NSString *tail=[path substringFromIndex:prefix.length];
        NSArray<NSString *> *parts=[tail componentsSeparatedByString:@"/"];
        if (parts.count<3 || !parts.firstObject.length) continue;
        root=[prefix stringByAppendingString:parts.firstObject];
        relative=[[parts subarrayWithRange:NSMakeRange(1,parts.count-1)] componentsJoinedByString:@"/"];
        break;
    }
    if (!root || !WQPValidPath(relative) || wq_is_backup_storage_path(path)) {
        if (error) *error=@"Hãy chọn tệp nằm trong Documents, Library hoặc tmp của một ứng dụng.";
        return nil;
    }
    struct stat st;
    if (!wq_stat(path,&st) || !S_ISREG(st.st_mode)) {
        if (error) *error=@"Đường dẫn đã chọn không phải tệp thường hoặc không thể truy cập.";
        return nil;
    }
    NSString *bundle=wq_bundle_id_for_container(root);
    if (!WQPValidBundle(bundle)) bundle=wq_container_label(root);
    if (!WQPValidBundle(bundle)) {
        if (error) *error=@"Không xác định được Bundle ID từ thư mục ứng dụng. Kiểm tra lại ứng dụng đích.";
        return nil;
    }
    return @{@"bundleID":bundle,@"relativePath":relative,@"absolutePath":path};
}

static NSString *WQPItemType(mode_t mode) {
    if (S_ISLNK(mode)) return @"liên kết tượng trưng";
    if (S_ISDIR(mode)) return @"thư mục";
    if (S_ISSOCK(mode)) return @"socket";
    if (S_ISFIFO(mode)) return @"ống dữ liệu";
    if (S_ISCHR(mode) || S_ISBLK(mode)) return @"tệp thiết bị";
    return @"mục không phải tệp thông thường";
}
static BOOL WQPSafeParents(NSString *root, NSString *target) {
    NSString *parent=target.stringByDeletingLastPathComponent;
    while (![parent isEqualToString:root]) {
        if (![parent hasPrefix:[root stringByAppendingString:@"/"]]) return NO;
        struct stat st;
        if (!wq_stat(parent,&st) || !S_ISDIR(st.st_mode)) return NO;
        parent=parent.stringByDeletingLastPathComponent;
    }
    return YES;
}
// Convert the codec's technical error codes to Vietnamese at the presentation layer.
// Keep the codec error identifiers stable so package parsing/compatibility is unchanged.
static NSString *WQPVietnameseCodecError(NSString *reason) {
    if (![reason isKindOfClass:NSString.class] || reason.length == 0)
        return @"Không xác định được nguyên nhân.";
    if ([reason hasPrefix:@"unsupported 3105 schema v"]) {
        NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"schema v([0-9]+)"
            options:0 error:nil];
        NSTextCheckingResult *match=[re firstMatchInString:reason options:0 range:NSMakeRange(0,reason.length)];
        NSString *version=match ? [reason substringWithRange:[match rangeAtIndex:1]] : @"không xác định";
        return [NSString stringWithFormat:@"Gói .3105 sử dụng phiên bản định dạng %@ chưa được hỗ trợ đầy đủ.",version];
    }
    NSDictionary<NSString *, NSString *> *messages=@{
        @"password_required":@"Gói patch có mật khẩu. Vui lòng nhập mật khẩu.",
        @"invalid key size":@"Kích thước khóa mã hóa không hợp lệ.",
        @"invalid password parameters":@"Tham số bảo vệ bằng mật khẩu không hợp lệ.",
        @"key derivation failed":@"Không thể tạo khóa giải mã từ mật khẩu.",
        @"not a 3105 file":@"Tệp được chọn không phải gói patch .3105 hợp lệ.",
        @"missing public key":@"Gói patch thiếu khóa giải mã cần thiết.",
        @"incorrect password or corrupted package":@"Mật khẩu không đúng hoặc gói patch bị hỏng.",
        @"Unsupported v9 payload structure":@"Cấu trúc dữ liệu của gói patch v9 không được hỗ trợ.",
        @"v9 package requires App Group, settings or unsupported fields; cannot safely apply here":@"Gói patch v9 chứa App Group, thiết lập hoặc trường dữ liệu chưa được hỗ trợ; không thể áp dụng an toàn.",
        @"v9 directory operation requires unsupported container type":@"Gói patch v9 sử dụng loại vùng dữ liệu không được hỗ trợ.",
        @"v9 rule uses mergePlist, mergeJson, App Group or unsupported operation; not safe to apply as replacement":@"Gói patch v9 yêu cầu gộp dữ liệu hoặc thao tác chưa được hỗ trợ; không thể thay thế tệp một cách an toàn.",
        @"v9 private patch must be password-protected":@"Gói patch riêng tư v9 phải được bảo vệ bằng mật khẩu.",
        @"package ID mismatch":@"Mã định danh gói patch không khớp.",
        @"invalid number of rules":@"Số lượng quy tắc trong gói patch không hợp lệ.",
        @"Unsupported v9 patch operation/container":@"Thao tác hoặc vùng dữ liệu trong gói patch v9 không được hỗ trợ.",
        @"file integrity check failed":@"Tệp trong gói patch không vượt qua kiểm tra tính toàn vẹn.",
        @"duplicate or oversized file":@"Gói patch chứa tệp trùng lặp hoặc vượt quá giới hạn kích thước.",
        @"package has no file replacements":@"Gói patch không có tệp thay thế.",
        @"package is empty or too large":@"Gói patch trống hoặc quá lớn.",
        @"import error":@"Không thể nhập gói patch.",
        @"incorrect password, corrupted package, or unsupported 3105 schema":@"Mật khẩu không đúng, tệp bị hỏng hoặc phiên bản gói patch chưa được hỗ trợ.",
        @"secure random generator failed":@"Không thể tạo khóa mã hóa ngẫu nhiên.",
        @"AES-GCM failed":@"Không thể mã hóa dữ liệu gói patch.",
        @"invalid patch name or file list":@"Tên patch hoặc danh sách tệp không hợp lệ.",
        @"invalid bundle identifier or target path":@"Mã ứng dụng hoặc đường dẫn đích không hợp lệ.",
        @"duplicate target, invalid base64 or file larger than 8 MiB":@"Tệp đích bị trùng, nội dung không hợp lệ hoặc vượt quá 8 MB.",
        @"missing patch description":@"Thiếu thông tin để tạo patch.",
        @"unable to create 3105 package":@"Không thể tạo gói patch .3105."
    };
    NSString *localized=messages[reason];
    if (localized) return localized;
    // Preserve an unknown technical reason for diagnosis, but label it in Vietnamese.
    return [NSString stringWithFormat:@"Không thể xử lý gói patch. Chi tiết kỹ thuật: %@",reason];
}

@interface WQPatchViewController ()
@property(nonatomic,copy) NSArray<NSDictionary *> *rules;
@property(nonatomic,copy) NSString *patchName;
@property(nonatomic,copy) NSString *lastTransaction;
@property(nonatomic,copy) NSString *pendingImportPath;
@property(nonatomic,copy) NSString *pendingCreatePath;
@property(nonatomic,strong) NSURL *pendingImportURL;
@property(nonatomic,copy) NSString *draftName;
@property(nonatomic,copy) NSString *draftBundle;
@property(nonatomic,copy) NSString *draftPath;
@property(nonatomic,copy) NSString *draftPassword;
@property(nonatomic) BOOL waitingForDraftFile;
@property(nonatomic,copy) NSString *searchText;
@property(nonatomic,copy) NSArray<NSDictionary *> *installedPatches;
@property(nonatomic,copy) NSString *selectedPatchID;
@property(nonatomic) BOOL reopenForActions;
@property(nonatomic) BOOL mutationInProgress;
@property(nonatomic,copy) NSDictionary<NSString *, NSString *> *activeByHash;
@end
@implementation WQPatchViewController
- (instancetype)init {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title=@"Đã cài"; self.patchName=@"Chưa chọn patch";
    }
    return self;
}
- (instancetype)initWithImportFilePath:(NSString *)path {
    if ((self=[self init])) self.pendingImportPath=[path copy];
    return self;
}
- (instancetype)initWithImportURL:(NSURL *)url {
    if ((self=[self init])) self.pendingImportURL=url;
    return self;
}
+ (BOOL)canCreatePatchFromFilePath:(NSString *)path {
    if (![path isKindOfClass:NSString.class] || !path.length) return NO;
    NSString *normalized=[path stringByStandardizingPath];
    return [normalized hasPrefix:@"/private/var/mobile/Containers/Data/Application/"] ||
           [normalized hasPrefix:@"/var/mobile/Containers/Data/Application/"] ||
           [normalized hasPrefix:@"/private/var/containers/Data/Application/"];
}
- (instancetype)initWithCreateFromFilePath:(NSString *)path {
    if ((self=[self init])) self.pendingCreatePath=[path copy];
    return self;
}
- (void)prepareCreateFromSelectedFile:(NSString *)filePath {
    dispatch_async(wq_io(), ^{
        NSString *error=nil;
        NSDictionary *item=WQPDescribeAppFile(filePath,&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!item) {
                [self alert:@"Không thể tạo patch từ tệp" message:error ?: @"Không xác định được đường dẫn tệp."];
                return;
            }
            self.draftBundle=item[@"bundleID"];
            self.draftPath=item[@"relativePath"];
            self.draftName=[NSString stringWithFormat:@"Patch - %@",self.draftPath.lastPathComponent];
            self.draftPassword=@"";
            [self startCreate];
        });
    });
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadPatchCatalog];
    [self findTransaction];
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.backgroundColor=UIColor.blackColor;
    self.tableView.separatorStyle=UITableViewCellSeparatorStyleNone;
    self.tableView.tintColor=[UIColor colorWithRed:0.58 green:0.49 blue:1.0 alpha:1.0];
    UISearchBar *search=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,self.tableView.bounds.size.width,68)];
    search.placeholder=@"Tìm patch đã nhập";
    search.searchBarStyle=UISearchBarStyleMinimal;
    search.delegate=self;
    search.autocapitalizationType=UITextAutocapitalizationTypeNone;
    search.autocorrectionType=UITextAutocorrectionTypeNo;
    self.tableView.tableHeaderView=search;
    __weak typeof(self) weakSelf=self;
    UIAction *create=[UIAction actionWithTitle:@"Tạo patch" image:[UIImage systemImageNamed:@"doc.badge.plus"] identifier:nil handler:^(UIAction *__unused action) {
        [weakSelf startCreate];
    }];
    UIAction *import=[UIAction actionWithTitle:@"Nhập .3105" image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(UIAction *__unused action) {
        [weakSelf pick];
    }];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"] menu:[UIMenu menuWithChildren:@[create,import]]];
    if (self.presentingViewController && self.navigationController.viewControllers.count==1) {
        self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
            target:self action:@selector(closePatch)];
    }
}
- (void)closePatch {
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadPatchCatalog];
    [self findTransaction];
    [self.tableView reloadData];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.navigationController.presentingViewController &&
        self.navigationController.viewControllers.firstObject==self &&
        !self.navigationItem.leftBarButtonItem) {
        self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
             initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closePatch)];
    }
    if (self.pendingCreatePath.length) {
        NSString *path=self.pendingCreatePath; self.pendingCreatePath=nil;
        [self prepareCreateFromSelectedFile:path];
    } else if (self.pendingImportPath.length) {
        NSString *path=self.pendingImportPath; self.pendingImportPath=nil;
        dispatch_async(wq_io(), ^{
            NSString *err=nil; NSData *data=wq_read(path,64*1024*1024+1,&err);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!data || data.length>64*1024*1024) [self alert:@"Không thể nhập patch" message:err?:@"Tệp không đọc được hoặc vượt 64 MB"];
                else [self importData:data password:nil];
            });
        });
    } else if (self.pendingImportURL) {
        NSURL *url=self.pendingImportURL; self.pendingImportURL=nil;
        [self importExternalURL:url];
    }
}
- (void)importExternalURL:(NSURL *)url {
    if (![[url.pathExtension lowercaseString] isEqualToString:@"3105"]) {
        [self alert:@"Không hỗ trợ" message:@"Chỉ nhận gói .3105"]; return;
    }
    BOOL scope=[url startAccessingSecurityScopedResource];
    NSData *data=[NSData dataWithContentsOfURL:url options:0 error:nil];
    if (scope) [url stopAccessingSecurityScopedResource];
    if (!data || data.length>64*1024*1024) {
        [self alert:@"Không thể nhập patch" message:@"Tệp không đọc được hoặc vượt 64 MB"]; return;
    }
    [self importData:data password:nil];
}
// Read all unfinished journals; their original-path records reserve those targets
// until the matching package is restored. A prepared or partially applied patch
// still owns its targets, so another patch must not overwrite them.
- (NSArray<NSDictionary *> *)activeTransactions {
    NSMutableArray<NSDictionary *> *active=NSMutableArray.new;
    NSArray<NSString *> *folders=[[NSFileManager.defaultManager
        contentsOfDirectoryAtPath:WQPStore() error:nil]
        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *folder in folders) {
        NSString *dir=[WQPStore() stringByAppendingPathComponent:folder];
        NSDictionary *journal=WQPRead([dir stringByAppendingPathComponent:@"journal.json"]);
        if (!journal) continue;
        NSString *state=journal[@"state"];
        if ([state isEqualToString:@"restored"] || [state isEqualToString:@"failed-preflight"])
            continue;
        [active addObject:@{@"directory":dir,@"journal":journal}];
    }
    return active;
}
- (void)findTransaction {
    NSArray<NSDictionary *> *active=[self activeTransactions];
    NSMutableDictionary<NSString *,NSString *> *mapping=NSMutableDictionary.new;
    for (NSDictionary *item in active) {
        NSDictionary *journal=item[@"journal"];
        NSString *hash=journal[@"packageHash"];
        if ([hash isKindOfClass:NSString.class] && hash.length) mapping[hash]=item[@"directory"];
    }
    // Backward compatibility for pre-catalog backups without a package hash:
    // associate only when a legacy name matches exactly one installed package.
    for (NSDictionary *item in active) {
        NSDictionary *journal=item[@"journal"];
        if ([journal[@"packageHash"] isKindOfClass:NSString.class]) continue;
        NSString *name=journal[@"name"];
        if (![name isKindOfClass:NSString.class] || !name.length) continue;
        NSDictionary *matched=nil;
        for (NSDictionary *record in self.installedPatches) {
            if (![record[@"name"] isEqualToString:name]) continue;
            if (matched) {matched=nil; break;}
            matched=record;
        }
        NSString *hash=matched[@"hash"];
        if (hash && !mapping[hash]) mapping[hash]=item[@"directory"];
    }
    self.activeByHash=[mapping copy];
    self.lastTransaction=self.selectedPatchID?mapping[self.selectedPatchID]:nil;
}

- (NSString *)patchDir {
    NSString *root=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    return [root stringByAppendingPathComponent:@"Patches"];
}
- (NSString *)catalogPath { return [[self patchDir] stringByAppendingPathComponent:@"index.json"]; }
- (BOOL)validFilename:(NSString *)filename {
    if (![filename isKindOfClass:NSString.class] || filename.length>180 ||
        ![[filename.pathExtension lowercaseString] isEqualToString:@"3105"]) return NO;
    NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"] invertedSet];
    return [filename rangeOfCharacterFromSet:invalid].location==NSNotFound &&
        ![filename containsString:@".."];
}
- (NSString *)pathFor:(NSDictionary *)record {
    NSString *filename=record[@"file"];
    return [self validFilename:filename]?[[self patchDir] stringByAppendingPathComponent:filename]:nil;
}
- (BOOL)saveCatalog:(NSArray *)records {
    return WQPWrite(@{@"version":@1,@"patches":records},self.catalogPath);
}
- (void)loadPatchCatalog {
    NSString *dir=self.patchDir;
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray *saved=WQPRead(self.catalogPath)[@"patches"];
    NSMutableArray *catalog=NSMutableArray.new;
    NSMutableSet *seen=NSMutableSet.new;
    if ([saved isKindOfClass:NSArray.class]) for (id item in saved) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *hash=item[@"hash"],*file=item[@"file"],*name=item[@"name"];
        if (![hash isKindOfClass:NSString.class] || hash.length!=64 ||
            ![self validFilename:file] || ![name isKindOfClass:NSString.class] ||
            [seen containsObject:hash] ||
            ![NSFileManager.defaultManager fileExistsAtPath:[dir stringByAppendingPathComponent:file]]) continue;
        [catalog addObject:item]; [seen addObject:hash];
    }
    // Recover every encrypted .3105 file from older builds, including packages
    // which were hidden by the old "last imported patch" singleton.
    NSString *legacy=[NSUserDefaults.standardUserDefaults stringForKey:@"WQPatchLastFile"];
    NSString *legacyName=[NSUserDefaults.standardUserDefaults stringForKey:@"WQPatchLastName"];
    NSArray *files=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil]
        sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *filename in files) {
        if (![self validFilename:filename]) continue;
        NSString *path=[dir stringByAppendingPathComponent:filename];
        NSData *content=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        if (!content || content.length>64*1024*1024 || !content.length) continue;
        NSString *hash=WQPHash(content);
        if ([seen containsObject:hash]) continue;
        NSString *name=[path isEqualToString:legacy] && legacyName.length?
             legacyName:[NSString stringWithFormat:@"Patch %@",[hash substringToIndex:8]];
        [catalog addObject:@{@"hash":hash,@"file":filename,@"name":name,@"count":@0,@"schema":@0}];
        [seen addObject:hash];
    }
    self.installedPatches=[catalog copy];
    [self saveCatalog:self.installedPatches];
}
- (NSArray *)visiblePatches {
    if (!self.searchText.length) return self.installedPatches?:@[];
    NSMutableArray *out=NSMutableArray.new;
    for (NSDictionary *item in self.installedPatches) {
        if ([item[@"name"] rangeOfString:self.searchText options:NSCaseInsensitiveSearch].location!=NSNotFound)
            [out addObject:item];
    }
    return out;
}
- (BOOL)registerPackage:(NSData *)data name:(NSString *)name count:(NSUInteger)count schema:(NSNumber *)schema {
    NSString *dir=self.patchDir;
    if (![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    NSString *hash=WQPHash(data);
    NSString *filename=[hash stringByAppendingPathExtension:@"3105"];
    NSString *path=[dir stringByAppendingPathComponent:filename];
    if (![NSFileManager.defaultManager fileExistsAtPath:path] &&
        ![data writeToFile:path options:NSDataWritingAtomic error:nil]) return NO;
    NSDictionary *entry=@{@"hash":hash,@"file":filename,
        @"name":name.length?name:@"Patch",@"count":@(count),@"schema":schema?:@0};
    NSMutableArray *catalog=[self.installedPatches mutableCopy]?:NSMutableArray.new;
    NSUInteger match=NSNotFound;
    for (NSUInteger i=0;i<catalog.count;i++)
        if ([catalog[i][@"hash"] isEqualToString:hash]) {match=i; break;}
    if (match==NSNotFound) [catalog addObject:entry]; else catalog[match]=entry;
    if (![self saveCatalog:catalog]) return NO;
    self.installedPatches=[catalog copy]; self.selectedPatchID=hash; self.patchName=entry[@"name"];
    [self findTransaction];
    [self.tableView reloadData];
    return YES;
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    self.searchText=text?:@""; [self.tableView reloadData];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *__unused)tableView { return 1; }
- (NSInteger)tableView:(UITableView *__unused)tableView numberOfRowsInSection:(NSInteger)__unused section {
    return (NSInteger)self.visiblePatches.count;
}
- (NSString *)tableView:(UITableView *__unused)tableView titleForHeaderInSection:(NSInteger)__unused section {
    NSUInteger active=self.activeByHash.count;
    return active?[NSString stringWithFormat:@"Patch · %lu đang áp dụng",(unsigned long)active]:@"Patch";
}
- (CGFloat)tableView:(UITableView *__unused)tableView heightForRowAtIndexPath:(NSIndexPath *__unused)indexPath {
    return 116;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"WQPatchCard"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"WQPatchCard"];
    NSDictionary *item=self.visiblePatches[indexPath.row];
    cell.backgroundColor=[UIColor colorWithWhite:0.115 alpha:1];
    cell.contentView.backgroundColor=cell.backgroundColor;
    cell.layer.cornerRadius=25; cell.layer.masksToBounds=YES;
    cell.selectionStyle=UITableViewCellSelectionStyleDefault;
    cell.textLabel.text=item[@"name"];
    cell.textLabel.textColor=UIColor.whiteColor;
    cell.textLabel.font=[UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
    NSUInteger count=[item[@"count"] unsignedIntegerValue];
    NSString *detail=count
        ?[NSString stringWithFormat:@"Patch · .3105 · %lu tệp",(unsigned long)count]
        :@"Patch · .3105 · Chạm để xem";
    if (self.activeByHash[item[@"hash"]]) detail=[detail stringByAppendingString:@" · Đang áp dụng"];
    cell.detailTextLabel.text=detail;
    cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    cell.detailTextLabel.font=[UIFont systemFontOfSize:15];
    UIImageSymbolConfiguration *symbol=[UIImageSymbolConfiguration configurationWithPointSize:27 weight:UIImageSymbolWeightMedium];
    cell.imageView.image=[UIImage systemImageNamed:@"shippingbox.fill" withConfiguration:symbol];
    cell.imageView.tintColor=[UIColor colorWithRed:0.59 green:0.52 blue:1.0 alpha:1.0];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item=self.visiblePatches[indexPath.row];
    if ([self.selectedPatchID isEqualToString:item[@"hash"]] && self.rules.count) {
        [self presentPatchActions]; return;
    }
    NSString *path=[self pathFor:item];
    NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;
    if (!data) { [self alert:@"Không thể mở patch" message:@"Không đọc được gói đã lưu. Hãy nhập lại tệp .3105."]; return; }
    self.reopenForActions=YES;
    [self importData:data password:nil];
}
- (void)presentPatchActions {
    [self findTransaction];
    NSDictionary *item=nil;
    for (NSDictionary *record in self.installedPatches)
        if ([record[@"hash"] isEqualToString:self.selectedPatchID]) { item=record; break; }
    if (!item) return;
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:item[@"name"]
        message:@"Chọn thao tác với gói .3105" preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Mở gói đã lưu" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *__unused action) {
            NSData *data=[NSData dataWithContentsOfFile:[self pathFor:item]];
            if (data) [self importData:data password:nil];
        }]];
    if (self.rules.count) [sheet addAction:[UIAlertAction actionWithTitle:@"Áp dụng patch"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused action) { [self confirmApply]; }]];
    if (self.lastTransaction) [sheet addAction:[UIAlertAction actionWithTitle:@"Khôi phục patch này"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused action) { [self confirmRestore]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Xóa khỏi danh sách" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *__unused action) { [self confirmDelete:item]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *pop=sheet.popoverPresentationController;
    if (pop) { pop.sourceView=self.view; pop.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),120,1,1); }
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)confirmDelete:(NSDictionary *)item {
    if (self.lastTransaction || self.mutationInProgress) {
        [self alert:@"Không thể xóa" message:@"Hãy khôi phục patch đang áp dụng trước khi xóa gói."];
        return;
    }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Xóa patch?"
        message:@"Chỉ xóa gói đã nhập; không thay đổi dữ liệu ứng dụng."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Xóa" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused action) {
        NSMutableArray *catalog=[self.installedPatches mutableCopy];
        [catalog removeObject:item];
        if (![self saveCatalog:catalog]) {
            [self alert:@"Không thể xóa" message:@"Không lưu được danh sách patch."]; return;
        }
        self.installedPatches=[catalog copy];
        if ([self.selectedPatchID isEqualToString:item[@"hash"]]) {
            self.selectedPatchID=nil; self.rules=nil; self.patchName=@"Chưa chọn patch";
        }
        NSString *path=[self pathFor:item];
        if (path) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)pick {
    // Do NOT restrict the picker to a dynamically inferred .3105 UTI or UTTypeData.
    // iOS Files may classify external .3105 packages as an unknown type and gray them out.
    // Public.item accepts files from third-party providers; the extension and magic bytes
    // are validated after selection, before any package is decoded or applied.
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate=self;
    picker.allowsMultipleSelection=NO;
    picker.shouldShowFileExtensions=YES;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject;
    if (!url) return;
    if (!self.waitingForDraftFile &&
        ![[url.pathExtension lowercaseString] isEqualToString:@"3105"]) {
        [self alert:@"Không hỗ trợ" message:@"Vui lòng chọn tệp .3105 (không cần đổi tên hoặc nén ZIP)"];
        return;
    }
    BOOL scope=[url startAccessingSecurityScopedResource];
    NSError *readError=nil;
    NSData *data=[NSData dataWithContentsOfURL:url options:0 error:&readError];
    if (scope) [url stopAccessingSecurityScopedResource];
    if (!data || data.length>64*1024*1024) {
        NSString *reason=readError.localizedDescription ?: @"Tệp không đọc được hoặc lớn hơn 64 MB";
        [self alert:@"Không thể đọc tệp" message:reason]; return;
    }
    if (self.waitingForDraftFile) {
        self.waitingForDraftFile=NO;
        [self exportDraftWithData:data];
        return;
    }
    if (![[url.pathExtension lowercaseString] isEqualToString:@"3105"]) {
        [self alert:@"Không hỗ trợ" message:@"Vui lòng chọn tệp có đuôi .3105"];
        return;
    }
    [self importData:data password:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.waitingForDraftFile=NO;
}
- (void)startCreate {
    UIAlertController *form=[UIAlertController alertControllerWithTitle:@"Tạo patch .3105"
        message:@"Nhập tên, bundle ID ứng dụng và đường dẫn tương đối đến tệp sẽ thay thế. Tiếp theo chọn nội dung từ Files."
        preferredStyle:UIAlertControllerStyleAlert];
    NSArray<NSString *> *placeholders=@[@"Tên patch", @"Bundle ID (com.example.app)", @"Đích (Documents/config.json)", @"Mật khẩu (có thể bỏ trống)"];
    NSArray<NSString *> *initial=@[self.draftName?:@"",self.draftBundle?:@"",self.draftPath?:@"",self.draftPassword?:@""];
    for (NSUInteger i=0;i<placeholders.count;i++) {
        NSString *placeholder=placeholders[i], *value=initial[i];
        [form addTextFieldWithConfigurationHandler:^(UITextField *f) {
            f.placeholder=placeholder;
            f.text=value;
            if (i==3) f.secureTextEntry=YES;
            f.autocorrectionType=UITextAutocorrectionTypeNo;
            f.autocapitalizationType=UITextAutocapitalizationTypeNone;
        }];
    }
    [form addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [form addAction:[UIAlertAction actionWithTitle:@"Chọn tệp" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused a) {
        self.draftName=form.textFields[0].text ?: @"";
        self.draftBundle=form.textFields[1].text ?: @"";
        self.draftPath=form.textFields[2].text ?: @"";
        self.draftPassword=form.textFields[3].text ?: @"";
        if (!self.draftName.length || !WQPValidBundle(self.draftBundle) || !WQPValidPath(self.draftPath)) {
            [self alert:@"Thông tin không hợp lệ" message:@"Kiểm tra tên, bundle ID và đường dẫn phải bắt đầu bằng Documents/, Library/ hoặc tmp/"];
            return;
        }
        self.waitingForDraftFile=YES;
        UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
        picker.delegate=self; picker.allowsMultipleSelection=NO;
        picker.shouldShowFileExtensions=YES;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [self presentViewController:form animated:YES completion:nil];
}
- (void)exportDraftWithData:(NSData *)payload {
    if (payload.length>8*1024*1024) {
        [self alert:@"Tệp quá lớn" message:@"Bản tạo patch thử nghiệm giới hạn 8 MB/tệp"]; return;
    }
    NSDictionary *draft=@{@"name":self.draftName ?: @"Patch",
        @"files":@[@{@"bundleID":self.draftBundle ?: @"", @"path":self.draftPath ?: @"",
                      @"data":[payload base64EncodedStringWithOptions:0]}]};
    NSData *json=[NSJSONSerialization dataWithJSONObject:draft options:0 error:nil];
    NSString *input=[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    char *raw=wq_create_3105(input.UTF8String,self.draftPassword.UTF8String);
    NSData *rawData=raw?[NSData dataWithBytes:raw length:strlen(raw)]:nil; free(raw);
    NSDictionary *response=rawData?[NSJSONSerialization JSONObjectWithData:rawData options:0 error:nil]:nil;
    NSString *encoded=response[@"base64"];
    NSData *package=[encoded isKindOfClass:NSString.class]?[[NSData alloc] initWithBase64EncodedString:encoded options:0]:nil;
    if (!package) {
        [self alert:@"Tạo patch thất bại" message:response[@"error"] ? WQPVietnameseCodecError(response[@"error"]) : @"Không thể mã hóa gói .3105"];
        return;
    }
    if (![self registerPackage:package name:self.draftName count:1 schema:@3]) {
        [self alert:@"Không thể lưu patch" message:@"Không thể lưu gói hoặc cập nhật danh sách đã cài."];
        self.draftPassword=nil; return;
    }
    self.rules=draft[@"files"];
    self.draftPassword=nil;
    [self alert:@"Đã tạo gói .3105" message:@"Đã thêm patch mới vào danh sách. Các patch trước đó được giữ nguyên."];
}
- (void)importData:(NSData *)data password:(NSString *)password {
    char *raw=wq_decode_3105(data.bytes,(intptr_t)data.length,password.UTF8String);
    NSData *bytes=raw?[NSData dataWithBytes:raw length:strlen(raw)]:nil;
    free(raw);
    NSDictionary *response=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil]:nil;
    NSString *error=response[@"error"];
    if ([error isEqualToString:@"password_required"] && !password.length) {
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Mật khẩu gói patch" message:@"Nhập mật khẩu để mở gói .3105." preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *field){ field.secureTextEntry=YES; }];
        [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Nhập patch" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused unused) {
            [self importData:data password:a.textFields.firstObject.text ?: @""];
        }]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    if (error || ![response[@"files"] isKindOfClass:NSArray.class]) {
        self.reopenForActions=NO;
        [self alert:@"Nhập patch thất bại" message:error ? WQPVietnameseCodecError(error) : @"Gói patch không hợp lệ hoặc không thể giải mã."]; return;
    }
    NSString *name=response[@"name"] ?: @"Patch đã nhập";
    NSArray *files=response[@"files"];
    if (![self registerPackage:data name:name count:files.count schema:response[@"schemaVersion"]]) {
        self.reopenForActions=NO;
        [self alert:@"Lưu patch thất bại" message:@"Không thể lưu gói hoặc cập nhật danh sách đã cài."];
        return;
    }
    self.rules=files;
    if (self.reopenForActions) {
        self.reopenForActions=NO;
        [self presentPatchActions];
    }
}
- (void)confirmApply {
    if (!self.rules.count || !self.selectedPatchID) return;
    if (self.mutationInProgress) {
        [self alert:@"Đang xử lý" message:@"Hãy hoàn thành thao tác hiện tại trước khi tiếp tục."]; return;
    }
    [self findTransaction];
    if (self.lastTransaction) {
        [self alert:@"Patch này đang hoạt động"
            message:@"Patch đã được áp dụng. Bạn có thể khôi phục riêng patch này hoặc chọn patch khác."];
        return;
    }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Áp dụng patch?" message:@"Hãy đóng ứng dụng đích trước khi tiếp tục. Hệ thống sẽ sao lưu dữ liệu gốc trước khi áp dụng." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Áp dụng" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused unused) { [self apply]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)apply {
    if (self.mutationInProgress) return;
    self.mutationInProgress=YES;
    NSArray *rules=[self.rules copy];
    NSString *name=[self.patchName copy];
    NSString *packageHash=[self.selectedPatchID copy];
    dispatch_async(wq_io(), ^{
        NSTimeInterval started=NSDate.timeIntervalSinceReferenceDate;
        NSString *err=nil;
        NSMutableArray<NSDictionary *> *preflight=NSMutableArray.new;
        NSMutableArray<NSData *> *payloads=NSMutableArray.new;
        NSMutableDictionary<NSString *, id> *locationCache=NSMutableDictionary.new;
        NSMutableSet *seen=NSMutableSet.new;
        NSMutableDictionary<NSString *,NSString *> *reservedTargets=NSMutableDictionary.new;
        NSMutableDictionary<NSString *,NSString *> *reservedKeys=NSMutableDictionary.new;
        // Recheck inside serialized WQ I/O immediately before mutation. This
        // also covers multiple Patch views trying to apply at the same time.
        for (NSDictionary *active in [self activeTransactions]) {
            NSDictionary *journal=active[@"journal"];
            NSString *owner=journal[@"name"] ?: @"patch đang áp dụng";
            if ([journal[@"packageHash"] isEqualToString:packageHash]) {
                err=@"Patch này đã được áp dụng hoặc chưa khôi phục xong.";
                break;
            }
            NSArray *records=journal[@"records"];
            if (![records isKindOfClass:NSArray.class] || records.count==0) {
                err=@"Có bản sao lưu đang hoạt động nhưng thiếu thông tin đích. Hãy xử lý bản sao lưu trước.";
                break;
            }
            for (NSDictionary *record in records) {
                if (![record isKindOfClass:NSDictionary.class]) {
                    err=@"Nhật ký patch đang hoạt động không hợp lệ."; break;
                }
                NSString *target=record[@"target"];
                NSString *bundle=record[@"bundle"], *relative=record[@"relative"];
                if (![target isKindOfClass:NSString.class] ||
                    ![bundle isKindOfClass:NSString.class] ||
                    ![relative isKindOfClass:NSString.class]) {
                    err=@"Nhật ký patch đang hoạt động thiếu đường dẫn tệp."; break;
                }
                reservedTargets[target]=owner;
                reservedKeys[[NSString stringWithFormat:@"%@\\0%@",bundle,relative]]=owner;
            }
            if (err) break;
        }
        NSString *dir=[WQPStore() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%013lld-%@", (long long)(NSDate.date.timeIntervalSince1970*1000),NSUUID.UUID.UUIDString]];
        BOOL made=YES;
        if (!err) made=[NSFileManager.defaultManager createDirectoryAtPath:dir
            withIntermediateDirectories:YES attributes:nil error:nil];
        if (!made) err=@"Không thể tạo thư mục sao lưu.";
        for (NSDictionary *item in rules) {
            if (err) break;
            NSString *bundle=item[@"bundleID"], *relative=item[@"path"];
            if (!WQPValidBundle(bundle) || !WQPValidPath(relative)) { err=@"Mã ứng dụng hoặc đường dẫn đích không hợp lệ."; break; }
            NSString *root=WQPLocateCached(bundle,locationCache);
            if (!root) { err=[NSString stringWithFormat:@"Không xác định được duy nhất thư mục của ứng dụng %@.",bundle]; break; }
            NSString *target=[root stringByAppendingPathComponent:relative];
            if (![target hasPrefix:[root stringByAppendingString:@"/"]] ||
                !WQPSafeParents(root,target) || wq_is_backup_storage_path(target)) { err=@"Thư mục đích không tồn tại hoặc đường dẫn không an toàn."; break; }
            NSString *logical=[NSString stringWithFormat:@"%@\0%@",bundle,relative];
            NSString *owner=reservedTargets[target] ?: reservedKeys[logical];
            // Reject parent/child overlaps too: a directory replaced with a file
            // must not invalidate another patch's journal for a nested target.
            if (!owner) for (NSString *used in reservedTargets) {
                if ([target hasPrefix:[used stringByAppendingString:@"/"]] ||
                    [used hasPrefix:[target stringByAppendingString:@"/"]]) {
                    owner=reservedTargets[used]; break;
                }
            }
            if (owner) {
                err=[NSString stringWithFormat:
                    @"Xung đột đường dẫn %@ với %@. Khôi phục patch cũ trước khi thay thế mục này.",relative,owner];
                break;
            }
            for (NSString *used in seen) {
                if ([used isEqualToString:target] ||
                    [used hasPrefix:[target stringByAppendingString:@"/"]] ||
                    [target hasPrefix:[used stringByAppendingString:@"/"]]) {
                    err=@"Gói patch có đường dẫn đích trùng hoặc lồng nhau."; break;
                }
            }
            if (err) break;
            [seen addObject:target];
            struct stat st;
            BOOL existed=wq_stat(target,&st);
            BOOL nonFile=existed && !S_ISREG(st.st_mode);
            // For directories, links and other filesystem objects, rename the
            // entire original to a sibling: zero-byte-copy backup, same volume,
            // preserving all nested contents, modes, links and other metadata.
            // No destructive operation begins until this name is in the journal.
            NSString *shadow=@"";
            NSDictionary *identity=nonFile ? wq_item_identity(target) : nil;
            if (nonFile) {
                if (!identity) { err=@"Không thể ghi nhận định danh của mục gốc."; break; }
                shadow=[target.stringByDeletingLastPathComponent stringByAppendingPathComponent:
                        [NSString stringWithFormat:@".wqpatch-original-%@",NSUUID.UUID.UUIDString]];
                struct stat backupSt;
                if (wq_stat(shadow,&backupSt)) {
                    err=@"Không tạo được tên sao lưu tạm không trùng."; break;
                }
            }
            NSData *replacement=[[NSData alloc] initWithBase64EncodedString:item[@"data"] options:0];
            if (!replacement || replacement.length>8*1024*1024) { err=@"Dữ liệu thay thế không hợp lệ hoặc vượt quá 8 MB."; break; }
            NSData *original=nil;
            if (existed && !nonFile) {
                original=wq_read(target,8*1024*1024+1,&err);
                if (!original || original.length>8*1024*1024) { err=err ?: @"Không thể sao lưu tệp đích lớn hơn 8 MB."; break; }
                NSString *backup=[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu.original",(unsigned long)preflight.count]];
                if (![original writeToFile:backup options:NSDataWritingAtomic error:nil]) { err=@"Không thể lưu bản sao dữ liệu gốc."; break; }
            }
            NSDictionary *version=existed && !nonFile?wq_file_version(target):nil;
            if (existed && !nonFile && !version) { err=@"Không thể xác minh phiên bản hiện tại của tệp đích."; break; }
            // Decode once and keep the original shadow path in the durable journal.
            [preflight addObject:@{@"bundle":bundle,@"relative":relative,@"target":target,
                @"hadOriginal":@(existed), @"originalHash":original?WQPHash(original):@"",
                @"appliedHash":WQPHash(replacement), @"number":@(preflight.count),
                @"version":version?:@{}, @"shadow":shadow,
                @"originalIdentity":identity?:@{},
                @"originalType":nonFile?WQPItemType(st.st_mode):@"file"}];
            [payloads addObject:replacement];
        }
        BOOL prepared=(err==nil);
        NSMutableDictionary *journal=[@{@"name":name,@"packageHash":packageHash,
                                          @"state":prepared?@"prepared":@"failed-preflight",
                                          @"records":[preflight copy]} mutableCopy];
        NSString *journalPath=[dir stringByAppendingPathComponent:@"journal.json"];
        if (made && !WQPWrite(journal,journalPath)) err=err?:@"Không thể lưu nhật ký sao lưu và khôi phục.";
        if (!err) for (NSUInteger i=0; i<preflight.count; i++) {
            NSDictionary *rec=preflight[i];
            NSData *data=payloads[i];
            NSString *shadow=rec[@"shadow"];
            BOOL success=NO;
            if ([shadow isKindOfClass:NSString.class] && shadow.length) {
                // Preserve the complete original, regardless of whether it is a
                // directory or a symbolic link, then put the patch bytes at
                // precisely the requested destination path.
                BOOL moved=wq_rename_expecting(rec[@"target"],shadow.lastPathComponent,
                                              rec[@"originalIdentity"],&err);
                if (moved) success=wq_create_file(rec[@"target"],data,&err);
            } else {
                success=[rec[@"hadOriginal"] boolValue]
                    ? wq_write_if_unchanged(rec[@"target"],data,rec[@"version"],&err)
                    : wq_create_file(rec[@"target"],data,&err);
            }
            if (!success) { err=err?:@"Áp dụng patch thất bại; mục gốc được giữ để khôi phục."; break; }
        }
        journal[@"state"]=prepared?(err?@"needs-restore":@"applied"):@"failed-preflight";
        if (made) WQPWrite(journal,journalPath);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.mutationInProgress=NO;
            [self findTransaction]; [self.tableView reloadData];
            NSTimeInterval elapsed=NSDate.timeIntervalSinceReferenceDate-started;
            [self alert:err?@"Áp dụng patch chưa hoàn tất":@"Áp dụng patch thành công"
                message:err?:[NSString stringWithFormat:@"Đã áp dụng %lu tệp trong %.2f giây. Bản sao lưu được giữ lại.",
                    (unsigned long)preflight.count,elapsed]];
        });
    });
}
- (void)confirmRestore {
    [self findTransaction];
    if (!self.lastTransaction || self.mutationInProgress) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Khôi phục patch?" message:@"Chỉ khôi phục khi tệp đích vẫn khớp với dữ liệu patch đã áp dụng. Nếu tệp đã thay đổi, hệ thống sẽ từ chối ghi đè." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Khôi phục" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused unused){ [self restore]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)restore {
    [self findTransaction];
    if (self.mutationInProgress || !self.lastTransaction) return;
    self.mutationInProgress=YES;
    NSString *dir=[self.lastTransaction copy];
    dispatch_async(wq_io(), ^{
        NSTimeInterval started=NSDate.timeIntervalSinceReferenceDate;
        NSMutableDictionary<NSString *, id> *locationCache=NSMutableDictionary.new;
        NSString *journalPath=[dir stringByAppendingPathComponent:@"journal.json"];
        NSMutableDictionary *journal=[WQPRead(journalPath) mutableCopy];
        NSArray *recs=journal[@"records"];
        NSString *err=recs?nil:@"Không tìm thấy nhật ký khôi phục.";
        for (NSDictionary *rec in recs.reverseObjectEnumerator) {
            if (err) break;
            NSString *root=WQPLocateCached(rec[@"bundle"],locationCache);
            NSString *target=root?[root stringByAppendingPathComponent:rec[@"relative"]]:nil;
            if (!root || ![target isEqualToString:rec[@"target"]] || !WQPSafeParents(root,target)) {
                err=@"Thư mục ứng dụng hoặc tệp đích đã thay đổi."; break;
            }
            struct stat st;
            BOOL exists=wq_stat(target,&st);
            if (!exists) {
                if ([rec[@"hadOriginal"] boolValue]) { err=@"Không tìm thấy tệp gốc; cần kiểm tra và khôi phục thủ công."; break; }
                continue;
            }
            if (!S_ISREG(st.st_mode)) { err=@"Loại tệp đích đã thay đổi."; break; }
            NSData *current=wq_read(target,8*1024*1024+1,&err);
            if (!current) { err=err?:@"Không thể đọc tệp đích."; break; }
            NSString *currentHash=WQPHash(current);
            if ([rec[@"hadOriginal"] boolValue] && [currentHash isEqualToString:rec[@"originalHash"]]) continue;
            if (![currentHash isEqualToString:rec[@"appliedHash"]]) {
                err=@"Tệp đích đã thay đổi sau khi áp dụng patch; hệ thống từ chối ghi đè."; break;
            }
            if ([rec[@"hadOriginal"] boolValue]) {
                NSString *backup=[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.original",rec[@"number"]]];
                NSData *original=[NSData dataWithContentsOfFile:backup];
                if (!original || ![WQPHash(original) isEqualToString:rec[@"originalHash"]]) {
                    err=@"Bản sao lưu không vượt qua kiểm tra tính toàn vẹn."; break;
                }
                NSDictionary *version=wq_file_version(target);
                if (!version || !wq_write_if_unchanged(target,original,version,&err)) {
                    err=err?:@"Khôi phục thất bại."; break;
                }
            } else {
                NSDictionary *identity=wq_item_identity(target);
                if (!identity || !wq_delete_expecting(target,identity,&err)) {
                    err=err?:@"Không thể xóa tệp được tạo thêm khi áp dụng patch."; break;
                }
            }
        }
        if (journal) {
            journal[@"state"]=err?@"needs-restore":@"restored";
            WQPWrite(journal,journalPath);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.mutationInProgress=NO;
            [self findTransaction]; [self.tableView reloadData];
            NSTimeInterval elapsed=NSDate.timeIntervalSinceReferenceDate-started;
            [self alert:err?@"Khôi phục chưa hoàn tất":@"Khôi phục thành công"
                message:err?:[NSString stringWithFormat:@"Đã khôi phục dữ liệu gốc hoặc xóa tệp được tạo thêm trong %.2f giây. Bản sao lưu vẫn được giữ lại.",elapsed]];
        });
    });
}
@end
