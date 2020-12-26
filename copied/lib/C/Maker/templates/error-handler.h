#ifndef ERROR_HANDLER_H
#define ERROR_HANDLER_H

typedef int (* error_handler_t) (const char * source_file,
                                 int source_line_number,
                                 const char * message, ...)
    __attribute__ ((format (printf, 3, 4)));

#endif /* ndef ERROR_HANDLER_H */

extern error_handler_t [% name_space %]_error_handler;
