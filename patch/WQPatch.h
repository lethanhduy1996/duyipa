#import <UIKit/UIKit.h>

@interface WQPatchViewController : UITableViewController <UIDocumentPickerDelegate, UISearchBarDelegate>
- (instancetype)initWithImportFilePath:(NSString *)path;
- (instancetype)initWithImportURL:(NSURL *)url;
@end
