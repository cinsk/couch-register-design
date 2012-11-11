
couch-register-design
=====================

This package provides utility scripts for interacting with CouchDB.


register-designs.rb
-------------------

Similar to [CouchApp](http://couchapp.org/), this script helps you to add/update CouchDB design document(s).

Key features are:

- Each function has its own file `.js`, and can have comments in it,
- Before uploading design document, all functions are checked for error(s),
- Attachments are supported,
- Unsupported design document contents are preserved between updates

### Design Document Hierachy
Your data (for the design document) should be placed in specific file system hierachy.  For example, if your design document name is "hello", then you need to create the directory, `hello/`.

All views of the design document should be placed in `views/` directory, and each view will have the directory with the view name, and each function of the view will be placed in that sub-directory. For show functions, they are placed in `shows/` directory.

Each function will have its own file with `.js` prefix.  Unlike [CouchApp](http://couchapp.org/) tool, you may have comments inside of the file.

Files in `_attachments/` will be automatically registered as
attachments to the design document.

Here's sample design document (hello) directory hierachy:

    hello/                              # design document, "hello"

    hello/views/byclass                 # view, "byclass"
    hello/views/byclass/map.js          # map function of "byclass"
    hello/views/byclass/reduce.js       # reduce function of "byclass"

    hello/shows/list.js                 # show function, "list"
    hello/shows/details.js              # show function, "details"

    hello/validate_doc_update.js        # validate_doc_update function

    hello/_attachments/                 # attachment files
    hello/_attachments/index.html       # attachment, "index.html"
    hello/_attachments/scripts/app.js   # attachment, "scripts/app.js"

Suppose your database name is "testdb", and CouchDB is running at your localhost, then you can register the design document, "hello" with following command:

    $ register-designs.rb -d http://localhost:5984/testdb hello


### Dependencies

- ruby verbsion 1.9.2p320 or higher
- [mime-types](https://github.com/halostatue/mime-types)
- curl(1) (`/usr/bin/curl`)
- Javascript interpreter, either [spidermonkey](https://developer.mozilla.org/en-US/docs/SpiderMonkey)(`js`) or [v8](http://code.google.com/p/v8/)(`v8`)

