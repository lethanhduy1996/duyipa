#import <UIKit/UIKit.h>

@interface WQPatchViewController : UITableViewController <UIDocumentPickerDelegate, UISearchBarDelegate>
- (instancetype)initWithImportFilePath:(NSString *)path;
- (instancetype)initWithImportURL:(NSURL *)url;
// Derive the bundle identifier and target relative path from a file in an app data container.
+ (BOOL)canCreatePatchFromFilePath:(NSString *)path;
- (instancetype)initWithCreateFromFilePath:(NSString *)path;
@end
