-- If the list of objects has been reviewed and everything looks good change @comitt = 1
DECLARE @comitt bit = 0


-- Delcare variables
DECLARE @database varchar(50)
DECLARE @object varchar(100)
DECLARE @objecttype varchar(50)
DECLARE @SQL nvarchar(MAX) = ''


CREATE TABLE #objectsToRemove (
	objectname VARCHAR(100),
	databasename varchar(50),
	objecttype varchar(50)	
);

-- A cursor which loops through the databases
DECLARE database_cursor CURSOR FOR
SELECT name FROM master.sys.databases WHERE name NOT IN ('master', 'model', 'msdb', 'SSISDB', 'tempdb')

OPEN database_cursor

FETCH NEXT FROM database_cursor INTO @database

WHILE @@FETCH_STATUS = 0
BEGIN
	-- Search for objects with a date in the name or a name containing: bak, old, test or depr
	SET @SQL = @SQL + 'INSERT INTO #objectsToRemove SELECT schema_name(o.schema_id) + ''.'' + NAME AS ObjectName, ''' + @database + ''', type_desc
	FROM ['+ @database + '].sys.objects o
	WHERE (o.NAME LIKE ''%201[0-8][0-9][0-9][0-9][0-9]%'' OR o.NAME LIKE ''%201[0-8][0-9][0-9]%''
	OR o.NAME LIKE ''%BAK%'' OR o.NAME LIKE ''%old%'' OR o.NAME LIKE ''%test%'' OR o.NAME LIKE ''%depr%'')
	AND type IN (''U'', ''V'', ''P'') ' -- Only look for user tables, views and stored procedures

	FETCH NEXT FROM database_cursor INTO @database
END
CLOSE database_cursor;
DEALLOCATE database_cursor;

EXECUTE sp_executesql @SQL;

-- Change object type to table respectivetly procedure
UPDATE #objectsToRemove
SET objecttype = 'TABLE'
WHERE objecttype = 'USER_TABLE'

UPDATE #objectsToRemove
SET objecttype = 'PROCEDURE'
WHERE objecttype = 'SQL_STORED_PROCEDURE'

-- Show the list of objects which are suggested to remove
SELECT * FROM #objectsToRemove

SET @SQL = '';

BEGIN
	-- Cursor to build the clean up code/script
	DECLARE drop_cursor CURSOR FOR
	SELECT objectname, databasename, objecttype FROM #objectsToRemove
	
	OPEN drop_cursor
	
	FETCH NEXT FROM drop_cursor INTO @object, @database, @objecttype
	
	WHILE @@FETCH_STATUS = 0
	BEGIN
		IF @objecttype = 'TABLE'
		BEGIN
			SET @SQL = @SQL + 'DROP ' + @objecttype + ' [' + @database + '].' + @object + ' '
		END
		ELSE BEGIN
			SET @SQL = @SQL + 'USE ' + @database + ' DROP ' + @objecttype + ' ' + @object + ' '
		END
	
		FETCH NEXT FROM drop_cursor INTO @object, @database, @objecttype
	END
	CLOSE drop_cursor;
	DEALLOCATE drop_cursor;
END

-- Clean up temp table
DROP TABLE #objectsToRemove
SELECT @SQL

IF @comitt = 1
BEGIN
	BEGIN TRANSACTION
		EXECUTE sp_executesql @SQL;
		PRINT @SQL + 'has been removed'
	COMMIT TRANSACTION
END
-- If @comitt = 0 you still get the code for deleting all sugested objects and can manually manipulate the code in case there are objects you want to keep
ELSE PRINT @SQL