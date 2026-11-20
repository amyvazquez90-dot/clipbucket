<?php
/**
 * PHP 8 compatibility shims for ClipBucket.
 *
 * ClipBucket was written for PHP 5.x / 7.x. A few functions used across the
 * codebase were removed in PHP 8. This file restores them so the existing
 * source keeps working unmodified. It is loaded for every request through
 * auto_prepend_file (see docker/php.ini).
 */

if (!function_exists('each')) {
    function each(&$array) {
        if (!is_array($array) && !is_object($array)) {
            return false;
        }
        $key = key($array);
        if ($key === null) {
            return false;
        }
        $value = current($array);
        next($array);
        return array(1 => $value, 'value' => $value, 0 => $key, 'key' => $key);
    }
}

if (!function_exists('split')) {
    function split($pattern, $string, $limit = -1) {
        return preg_split('/' . str_replace('/', '\/', $pattern) . '/', (string)$string, $limit);
    }
}

if (!function_exists('spliti')) {
    function spliti($pattern, $string, $limit = -1) {
        return preg_split('/' . str_replace('/', '\/', $pattern) . '/i', (string)$string, $limit);
    }
}

if (!function_exists('create_function')) {
    function create_function($args, $code) {
        return eval('return function(' . $args . ') {' . $code . '};');
    }
}

if (!function_exists('get_magic_quotes_gpc')) {
    function get_magic_quotes_gpc() { return false; }
}

if (!function_exists('get_magic_quotes_runtime')) {
    function get_magic_quotes_runtime() { return false; }
}

if (!function_exists('set_magic_quotes_runtime')) {
    function set_magic_quotes_runtime($value = false) { return false; }
}

if (!function_exists('mysql_escape_string')) {
    function mysql_escape_string($value) { return addslashes((string)$value); }
}

if (!function_exists('ereg')) {
    function ereg($pattern, $string, &$regs = null) {
        $regs = array();
        if (preg_match('/' . str_replace('/', '\/', $pattern) . '/', (string)$string, $matches)) {
            $regs = $matches;
            return strlen($matches[0]);
        }
        return false;
    }
}

if (!function_exists('eregi')) {
    function eregi($pattern, $string, &$regs = null) {
        $regs = array();
        if (preg_match('/' . str_replace('/', '\/', $pattern) . '/i', (string)$string, $matches)) {
            $regs = $matches;
            return strlen($matches[0]);
        }
        return false;
    }
}

if (!function_exists('money_format')) {
    function money_format($format, $number) {
        return sprintf('%01.2f', (float)$number);
    }
}
