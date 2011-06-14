#!/usr/bin/env python
# Python code to read/write/backup/delete dropbox config values for both 0.7.x and 0.8.x/1.0.x on all platforms
# Code blatantly 'stolen' from pyDropboxPath.py 0.8.3  :-)
# This file written by Andrew Scheller, 2010-10-14
# Updated by Andrew Scheller, 2010-11-09
# Updated by Andrew Scheller, 2011-01-01
# Updated by Andrew Scheller, 2011-01-12
#
# http://wiki.dropbox.com/DropboxAddons/PyDropboxValues

usage_txt = '''Usage:
pyDropboxValues.py
or
pyDropboxValues.py --help
or
pyDropboxValues.py [_printkeys|_linkurl|_raw|_backup|_dropbox]
'''

import os
import sys
import sqlite3
import base64
import pickle
import shutil

pickled_keys = set(('ns_p2p_key_map', 'recently_changed3', 'sandboxes', 'shadowed_proxy_password', 'last_update'))


def GetConfigDbDirectory():
	if sys.platform == 'win32':
		assert os.environ.has_key('APPDATA'), Exception('APPDATA env variable not found')
		dbpath = os.path.join(os.environ['APPDATA'],'Dropbox')
	elif sys.platform in ('linux2','darwin'):
		assert os.environ.has_key('HOME'), Exception('HOME env variable not found')
		dbpath = os.path.join(os.environ['HOME'],'.dropbox')
	else: # FIXME other archs?
		raise Exception('platform %s not known, please report' % sys.platform)
	return dbpath


def GetConfigDbFilename():
	dbpath = GetConfigDbDirectory()
	if os.path.isfile(os.path.join(dbpath,'config.db')):
		dbfn, dbfnver = os.path.join(dbpath,'config.db'), 1
	elif os.path.isfile(os.path.join(dbpath, 'dropbox.db')):
		dbfn, dbfnver = os.path.join(dbpath,'dropbox.db'), 0
	else:
		raise Exception('Dropbox database not found, is dropbox installed?')
	return (dbfn, dbfnver)


def GetDbConnection(dbfile):
	lastdir = os.getcwd()
	os.chdir(os.path.dirname(dbfile))
	connection = sqlite3.connect(os.path.basename(dbfile), isolation_level=None)
	os.chdir(lastdir)
	return connection


def GetDbVersion(dbfnver, connection):
	if dbfnver == 0: # dropbox.db, old-style
		dbver = 0
	elif dbfnver == 1: # config.db, can be upgraded, lets check schema
		cursor = connection.cursor()
		cursor.execute('SELECT value FROM config WHERE key="config_schema_version"')
		row = cursor.fetchone()
		cursor.close()
		dbver = row[0]
	return dbver


def GetDbKeys(connection):
	cursor = connection.cursor()
	cursor.execute('SELECT key FROM config')
	allkeys = set()
	for row in cursor:
		allkeys.add(row[0])
	cursor.close()
	return allkeys


# ReadDbValue can be called while dropbox is running
def ReadDbValue(connection, dbver, dbkey, decode_value=True):
	cursor = connection.cursor()
	# dup code now, but maybe someday it will be different
	if dbver == 0:
		cursor.execute('SELECT value FROM config WHERE key=?', (dbkey,))
	elif dbver == 1:
		cursor.execute('SELECT value FROM config WHERE key=?', (dbkey,))
	else:
		raise Exception('Unhandled DB schema version %d' % dbver)

	row = cursor.fetchone()
	cursor.close()
	if row is None:
		raise Exception('key %s not found in dropbox config database' % dbkey)
	else:
		dbvalue = row[0]
		if dbvalue and decode_value:
			if dbver == 0: # always pickled then b64encoded
				value = pickle.loads(base64.b64decode(dbvalue))
			elif dbver == 1: # some (non-string) values are still pickled
				if dbkey in pickled_keys:
					value = pickle.loads(dbvalue)
				else:
					value = dbvalue
			else:
				raise Exception('Unhandled DB schema version %d' % dbver)
		else:
			value = dbvalue
	return value


# WriteDbValue should only be called when dropbox is stopped
def WriteDbValue(connection, dbver, dbkey, value, encode_value=True):
	if encode_value:
		if dbver == 0: # always pickled then b64encoded
			dbvalue = base64.b64encode(pickle.dumps(value))
		elif dbver == 1: # some (non-string) values are still pickled
			if dbkey in pickled_keys:
				dbvalue = pickle.dumps(value)
			else:
				dbvalue = value
		else:
			raise Exception('Unhandled DB schema version %d' % dbver)
	else:
		dbvalue = value
	cursor = connection.cursor()
	cursor.execute('REPLACE INTO config (key,value) VALUES (?,?)', (dbkey,dbvalue))
	cursor.close()


# DeleteDbValue should only be called when dropbox is stopped
def DeleteDbValue(connection, dbver, dbkey):
	cursor = connection.cursor()
	cursor.execute('DELETE FROM config WHERE key=?', (dbkey,))
	cursor.close()


# Utility function - locate the user's "Dropbox" folder
def GetDropboxLocation(connection=None, dbver=None):
	if connection is None:
		dbfile, dbfnver = GetConfigDbFilename()
		connection = GetDbConnection(dbfile)
		dbver = GetDbVersion(dbfnver, connection)
	try:
		# first try to get path from config database
		dbfolder = ReadDbValue(connection, dbver, 'dropbox_path')
	except Exception, e:
		if str(e) == 'key %s not found in dropbox config database' % 'dropbox_path':
			# second try to get path from host.db
			dbpath = GetConfigDbDirectory()
			if os.path.isfile(os.path.join(dbpath,'host.db')):
				dbfolder = base64.b64decode(open(os.path.join(dbpath,'host.db')).readlines()[1])
			else:
				# finally just guess default path
				if sys.platform == 'win32':
					import ctypes
					dll = ctypes.windll.shell32
					buf = ctypes.create_string_buffer(300)
					dll.SHGetSpecialFolderPathA(None, buf, 0x0005, False)
					if dbver == 0:
						dbfolder = os.path.join(buf.value,'My Dropbox')
					else:
						dbfolder = os.path.join(buf.value,'Dropbox')
				elif sys.platform in ('linux2','darwin'):
					dbfolder = os.path.join(os.environ['HOME'],'Dropbox')
				else:
					raise Exception('platform %s not known, please report' % sys.platform)
		else:
			raise e
	return dbfolder


if __name__ == '__main__':
	dbfile, dbfnver = GetConfigDbFilename()
	connection = GetDbConnection(dbfile)
	dbver = GetDbVersion(dbfnver, connection)
	try:
		if len(sys.argv) == 1:
			for key in sorted(GetDbKeys(connection)):
				value = ReadDbValue(connection, dbver, key)
			 	print key, '=', value
		elif len(sys.argv) == 2:
			# hopefully there's never config values called _printkeys, _linkurl, _raw, _backup or _dropbox !
			if sys.argv[1] == '-h' or sys.argv[1] == '--help':
				print usage_txt
			elif sys.argv[1] == '_printkeys':
				print sorted(GetDbKeys(connection))
			elif sys.argv[1] == '_linkurl':
				value = ReadDbValue(connection, dbver, 'host_id')
				print "https://www.dropbox.com/cli_link?host_id=%s" % value
			elif sys.argv[1] == '_raw':
				for key in sorted(GetDbKeys(connection)):
					value = ReadDbValue(connection, dbver, key, False)
				 	print key, '=', value
			elif sys.argv[1] == '_backup':
				(basedir, basefile) = os.path.split(dbfile)
				backup_num = 1
				backup_filename = os.path.join(basedir, "backup_%d_%s" % (backup_num, basefile))
				while os.path.exists(backup_filename):
					backup_num += 1
					backup_filename = os.path.join(basedir, "backup_%d_%s" % (backup_num, basefile))
				shutil.copy2(dbfile, backup_filename)
				print "Backed up '%s' to '%s'" % (basefile, backup_filename)
			elif sys.argv[1] == '_dropbox':
				print GetDropboxLocation(connection, dbver)
			else:
				value = ReadDbValue(connection, dbver, sys.argv[1])
				print value
		else:
			print usage_txt
	except Exception as detail:
		print "An error occured: %s" % detail
	finally:
		connection.close()

