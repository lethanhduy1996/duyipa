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
@interface WQPatchViewController ()
@property(nonatomic,copy) NSArray<NSDictionary *> *rules;
@property(nonatomic,copy) NSString *patchName;
@property(nonatomic,copy) NSString *lastTransaction;
@property(nonatomic,copy) NSString *pendingImportPath;
@property(nonatomic,strong) NSURL *pendingImportURL;
@property(nonatomic,copy) NSString *draftName;
@property(nonatomic,copy) NSString *draftBundle;
@property(nonatomic,copy) NSString *draftPath;
@property(nonatomic,copy) NSString *draftPassword;
@property(nonatomic) BOOL waitingForDraftFile;
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
- (void)viewDidLoad {
    [super viewDidLoad];
    [self findTransaction];
    NSString *savedName=[NSUserDefaults.standardUserDefaults stringForKey:@"WQPatchLastName"];
    if (savedName.length) self.patchName=savedName;
    self.tableView.tintColor=[UIColor colorWithRed:0.58 green:0.49 blue:1.0 alpha:1.0];
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
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.navigationController.presentingViewController &&
        self.navigationController.viewControllers.firstObject==self &&
        !self.navigationItem.leftBarButtonItem) {
        self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
             initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closePatch)];
    }
    if (self.pendingImportPath.length) {
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
- (void)findTransaction {
    self.lastTransaction=nil;
    NSArray *folders=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:WQPStore() error:nil]
                      sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in folders.reverseObjectEnumerator) {
        NSString *path=[WQPStore() stringByAppendingPathComponent:name];
        NSDictionary *j=WQPRead([path stringByAppendingPathComponent:@"journal.json"]);
        if (j && ![@[@"restored",@"failed-preflight"] containsObject:j[@"state"]]) {
            self.lastTransaction=path; break;
        }
    }
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section==0?3:2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section==0?@"Patch":@"Áp dụng và khôi phục";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (indexPath.section==0 && indexPath.row==0) {
        cell.textLabel.text=@"Tạo patch";
        cell.detailTextLabel.text=@"Tạo và xuất gói .3105";
        cell.imageView.image=[UIImage systemImageNamed:@"doc.badge.plus"];
    } else if (indexPath.section==0 && indexPath.row==1) {
        cell.textLabel.text=@"Nhập .3105";
        cell.detailTextLabel.text=@"Chọn tệp trong Files, nhập cả gói có mật khẩu";
        cell.imageView.image=[UIImage systemImageNamed:@"square.and.arrow.down"];
    } else if (indexPath.section==0) {
        cell.textLabel.text=self.patchName;
        cell.detailTextLabel.text=self.rules?[NSString stringWithFormat:@"%lu verified replacement(s)",(unsigned long)self.rules.count]:@"Select a package in the Files app";
    } else if (indexPath.row==0) {
        cell.textLabel.text=@"Apply patch";
        cell.detailTextLabel.text=@"Backs up original bytes and records SHA-256";
        cell.textLabel.textColor=self.rules.count?UIColor.systemBlueColor:UIColor.secondaryLabelColor;
    } else {
        cell.textLabel.text=@"Restore original files";
        cell.detailTextLabel.text=self.lastTransaction?@"Active patch journal available":@"No active transaction";
        cell.textLabel.textColor=self.lastTransaction?UIColor.systemBlueColor:UIColor.secondaryLabelColor;
    }
    cell.detailTextLabel.numberOfLines=2;
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if (ip.section==0 && ip.row==0) [self startCreate];
    if (ip.section==0 && ip.row==1) [self pick];
    if (ip.section==0 && ip.row==2) {
        NSString *path=[NSUserDefaults.standardUserDefaults stringForKey:@"WQPatchLastFile"];
        NSData *saved=path.length?[NSData dataWithContentsOfFile:path]:nil;
        if (saved) [self importData:saved password:nil];
        else if (!self.rules.count) [self alert:@"Chưa có patch" message:@"Nhấn + để tạo patch hoặc chọn Nhập .3105"];
    }
    if (ip.section==1 && ip.row==0) [self confirmApply];
    if (ip.section==1 && ip.row==1) [self confirmRestore];
}
- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)pick {
    UTType *type=[UTType typeWithFilenameExtension:@"3105" conformingToType:UTTypeData];
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:type?@[type,UTTypeData]:@[UTTypeData]];
    picker.delegate=self; picker.allowsMultipleSelection=NO;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject;
    if (!url) return;
    BOOL scope=[url startAccessingSecurityScopedResource];
    NSData *data=[NSData dataWithContentsOfURL:url options:0 error:nil];
    if (scope) [url stopAccessingSecurityScopedResource];
    if (!data || data.length>64*1024*1024) {
        [self alert:@"Không thể đọc tệp" message:@"Tệp không tồn tại, không thể truy cập hoặc lớn hơn 64 MB"]; return;
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
    for (NSString *placeholder in placeholders) {
        [form addTextFieldWithConfigurationHandler:^(UITextField *f) {
            f.placeholder=placeholder;
            if ([placeholder hasPrefix:@"Mật khẩu"]) f.secureTextEntry=YES;
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
            initForOpeningContentTypes:@[UTTypeData]];
        picker.delegate=self; picker.allowsMultipleSelection=NO;
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
        [self alert:@"Tạo patch thất bại" message:response[@"error"] ?: @"Không thể mã hóa gói .3105"];
        return;
    }
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *directory=[documents stringByAppendingPathComponent:@"Patches"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *filename=[NSString stringWithFormat:@"%@.3105",NSUUID.UUID.UUIDString];
    NSString *path=[directory stringByAppendingPathComponent:filename];
    if (![package writeToFile:path options:NSDataWritingAtomic error:nil]) {
        [self alert:@"Không thể lưu patch" message:@"Kiểm tra bộ nhớ thiết bị"]; return;
    }
    self.patchName=self.draftName;
    self.rules=draft[@"files"];
    [self.tableView reloadData];
    [self alert:@"Đã tạo gói .3105" message:[NSString stringWithFormat:@"Đã lưu vào Tệp → Trên iPhone → WQ Files → Patches → %@. Có thể mở, chia sẻ hoặc nhập lại.",filename]];
}
- (void)importData:(NSData *)data password:(NSString *)password {
    char *raw=wq_decode_3105(data.bytes,(intptr_t)data.length,password.UTF8String);
    NSData *bytes=raw?[NSData dataWithBytes:raw length:strlen(raw)]:nil;
    free(raw);
    NSDictionary *response=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil]:nil;
    NSString *error=response[@"error"];
    if ([error isEqualToString:@"password_required"] && !password.length) {
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Patch password" message:@"Enter package password" preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *field){ field.secureTextEntry=YES; }];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused unused) {
            [self importData:data password:a.textFields.firstObject.text ?: @""];
        }]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    if (error || ![response[@"files"] isKindOfClass:NSArray.class]) {
        [self alert:@"Import failed" message:error ?: @"Invalid package"]; return;
    }
    self.patchName=response[@"name"] ?: @"Imported patch";
    self.rules=response[@"files"];
    // Save the original authenticated package; never persist the decrypted payload or its password.
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *dir=[documents stringByAppendingPathComponent:@"Patches"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path=[dir stringByAppendingPathComponent:[WQPHash(data) stringByAppendingPathExtension:@"3105"]];
    if ([data writeToFile:path options:NSDataWritingAtomic error:nil]) {
        [NSUserDefaults.standardUserDefaults setObject:path forKey:@"WQPatchLastFile"];
        [NSUserDefaults.standardUserDefaults setObject:self.patchName forKey:@"WQPatchLastName"];
    }
    [self.tableView reloadData];
}
- (void)confirmApply {
    if (!self.rules.count) return;
    if (self.lastTransaction) { [self alert:@"Active patch" message:@"Restore the active patch before applying a new one"]; return; }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Apply patch?" message:@"Close targeted apps first. A safety backup will be created." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused unused) { [self apply]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)apply {
    NSArray *rules=[self.rules copy];
    NSString *name=[self.patchName copy];
    dispatch_async(wq_io(), ^{
        NSString *err=nil;
        NSMutableArray *preflight=NSMutableArray.new;
        NSMutableSet *seen=NSMutableSet.new;
        NSString *dir=[WQPStore() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%013lld-%@", (long long)(NSDate.date.timeIntervalSince1970*1000),NSUUID.UUID.UUIDString]];
        BOOL made=[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        if (!made) err=@"Cannot create backup directory";
        for (NSDictionary *item in rules) {
            if (err) break;
            NSString *bundle=item[@"bundleID"], *relative=item[@"path"];
            if (!WQPValidBundle(bundle) || !WQPValidPath(relative)) { err=@"Invalid target bundle or path"; break; }
            NSString *root=WQPLocate(bundle);
            if (!root) { err=[NSString stringWithFormat:@"Cannot uniquely locate app %@",bundle]; break; }
            NSString *target=[root stringByAppendingPathComponent:relative];
            if (![target hasPrefix:[root stringByAppendingString:@"/"]] ||
                !WQPSafeParents(root,target) || wq_is_backup_storage_path(target)) { err=@"Unsafe or missing destination parent"; break; }
            if ([seen containsObject:target]) { err=@"Duplicate destination"; break; }
            [seen addObject:target];
            struct stat st;
            BOOL existed=wq_stat(target,&st);
            if (existed && !S_ISREG(st.st_mode)) { err=@"Target is not a regular file"; break; }
            NSData *replacement=[[NSData alloc] initWithBase64EncodedString:item[@"data"] options:0];
            if (!replacement || replacement.length>8*1024*1024) { err=@"Invalid or oversized payload"; break; }
            NSData *original=nil;
            if (existed) {
                original=wq_read(target,8*1024*1024+1,&err);
                if (!original || original.length>8*1024*1024) { err=err ?: @"Cannot back up target larger than 8 MB"; break; }
                NSString *backup=[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu.original",(unsigned long)preflight.count]];
                if (![original writeToFile:backup options:NSDataWritingAtomic error:nil]) { err=@"Writing original backup failed"; break; }
            }
            NSDictionary *version=existed?wq_file_version(target):nil;
            if (existed && !version) { err=@"Cannot verify target version"; break; }
            [preflight addObject:@{@"bundle":bundle,@"relative":relative,@"target":target,
                @"hadOriginal":@(existed), @"originalHash":original?WQPHash(original):@"",
                @"appliedHash":WQPHash(replacement), @"number":@(preflight.count),
                @"version":version?:@{},@"replacement":item[@"data"]}];
        }
        NSMutableArray *safe=NSMutableArray.new;
        for (NSDictionary *rec in preflight) {
            NSMutableDictionary *d=[rec mutableCopy]; [d removeObjectForKey:@"replacement"];
            [safe addObject:d];
        }
        BOOL prepared=(err==nil);
        NSMutableDictionary *journal=[@{@"name":name,@"state":prepared?@"prepared":@"failed-preflight", @"records":safe} mutableCopy];
        NSString *journalPath=[dir stringByAppendingPathComponent:@"journal.json"];
        if (!WQPWrite(journal,journalPath)) err=err?:@"Cannot write durable journal";
        if (!err) for (NSDictionary *rec in preflight) {
            NSData *data=[[NSData alloc] initWithBase64EncodedString:rec[@"replacement"] options:0];
            BOOL success=[rec[@"hadOriginal"] boolValue]
                ? wq_write_if_unchanged(rec[@"target"],data,rec[@"version"],&err)
                : wq_create_file(rec[@"target"],data,&err);
            if (!success) { err=err?:@"Patch failed; restore from journal"; break; }
        }
        journal[@"state"]=prepared?(err?@"needs-restore":@"applied"):@"failed-preflight";
        WQPWrite(journal,journalPath);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self findTransaction]; [self.tableView reloadData];
            [self alert:err?@"Apply incomplete":@"Patch applied"
                message:err?:[NSString stringWithFormat:@"%lu files applied; backups preserved.",(unsigned long)preflight.count]];
        });
    });
}
- (void)confirmRestore {
    if (!self.lastTransaction) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Restore patch?" message:@"Restore is refused if any target no longer matches the patch hash." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused unused){ [self restore]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)restore {
    NSString *dir=[self.lastTransaction copy];
    dispatch_async(wq_io(), ^{
        NSString *journalPath=[dir stringByAppendingPathComponent:@"journal.json"];
        NSMutableDictionary *journal=[WQPRead(journalPath) mutableCopy];
        NSArray *recs=journal[@"records"];
        NSString *err=recs?nil:@"Missing journal";
        for (NSDictionary *rec in recs.reverseObjectEnumerator) {
            if (err) break;
            NSString *root=WQPLocate(rec[@"bundle"]);
            NSString *target=root?[root stringByAppendingPathComponent:rec[@"relative"]]:nil;
            if (!root || ![target isEqualToString:rec[@"target"]] || !WQPSafeParents(root,target)) {
                err=@"Container or target identity changed"; break;
            }
            struct stat st;
            BOOL exists=wq_stat(target,&st);
            if (!exists) {
                if ([rec[@"hadOriginal"] boolValue]) { err=@"Original file is missing; manual recovery required"; break; }
                continue;
            }
            if (!S_ISREG(st.st_mode)) { err=@"File type changed"; break; }
            NSData *current=wq_read(target,8*1024*1024+1,&err);
            if (!current) { err=err?:@"Cannot read patch target"; break; }
            NSString *currentHash=WQPHash(current);
            if ([rec[@"hadOriginal"] boolValue] && [currentHash isEqualToString:rec[@"originalHash"]]) continue;
            if (![currentHash isEqualToString:rec[@"appliedHash"]]) {
                err=@"Patch target changed since application; refusing overwrite"; break;
            }
            if ([rec[@"hadOriginal"] boolValue]) {
                NSString *backup=[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.original",rec[@"number"]]];
                NSData *original=[NSData dataWithContentsOfFile:backup];
                if (!original || ![WQPHash(original) isEqualToString:rec[@"originalHash"]]) {
                    err=@"Backup integrity failure"; break;
                }
                NSDictionary *version=wq_file_version(target);
                if (!version || !wq_write_if_unchanged(target,original,version,&err)) {
                    err=err?:@"Restore failed"; break;
                }
            } else {
                NSDictionary *identity=wq_item_identity(target);
                if (!identity || !wq_delete_expecting(target,identity,&err)) {
                    err=err?:@"Could not remove added file"; break;
                }
            }
        }
        if (journal) {
            journal[@"state"]=err?@"needs-restore":@"restored";
            WQPWrite(journal,journalPath);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self findTransaction]; [self.tableView reloadData];
            [self alert:err?@"Restore incomplete":@"Restored"
                message:err?:@"Original bytes restored or newly created files removed. Backups retained."];
        });
    });
}
@end
