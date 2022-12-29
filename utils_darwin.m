void internal_show_alert(string s) {
    NSBeep();
    NSString* ns_string = nsstring(s);
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert setMessageText:ns_string];
    [alert setInformativeText:@""];
    [alert addButtonWithTitle:@"Ok"];
    [alert runModal];
}

string internal_open_file() {
    while(1) {
        NSOpenPanel* openDlg = [NSOpenPanel openPanel];
        [openDlg setCanChooseFiles:YES];
        [openDlg setTitle:@"Choose a Game Boy ROM"];
        [openDlg setShowsResizeIndicator:YES];
        [openDlg setShowsHiddenFiles:NO];
        [openDlg setCanChooseFiles:YES];
        [openDlg setCanChooseDirectories:NO];
        [openDlg setAllowsMultipleSelection:NO];
        [openDlg setAllowedFileTypes:@[@"gb",@"gbc"]];
        if([openDlg runModal] == NSFileHandlingPanelOKButton) {
            NSURL *selection = openDlg.URLs[0];
            NSString* path = [[selection path] stringByResolvingSymlinksInPath];
            return tos_clone(path.UTF8String);
        } else {
            NSBeep();
            NSAlert* alert = [[NSAlert alloc] init];
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert setMessageText:@"Please select a ROM in order to use Lugia"];
            [alert setInformativeText:@""];
            [alert addButtonWithTitle:@"Ok"];
            [alert runModal];
        }
    }
}