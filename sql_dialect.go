package main

import (
	"database/sql"
	"strconv"
	"strings"
)

var activeSQLDriver = "sqlite"

type dbRunner interface {
	Exec(query string, args ...any) (sql.Result, error)
	QueryRow(query string, args ...any) *sql.Row
}

func setSQLDriver(driver string) {
	driver = strings.TrimSpace(strings.ToLower(driver))
	if driver == "" {
		driver = "sqlite"
	}
	activeSQLDriver = driver
}

func sqlf(query string) string {
	if activeSQLDriver != "postgres" {
		return query
	}
	var b strings.Builder
	b.Grow(len(query) + 8)
	argIndex := 1
	for _, ch := range query {
		if ch == '?' {
			b.WriteByte('$')
			b.WriteString(strconv.Itoa(argIndex))
			argIndex++
			continue
		}
		b.WriteRune(ch)
	}
	return b.String()
}

func insertID(q dbRunner, query string, args ...any) (int, error) {
	if activeSQLDriver == "postgres" {
		var id int
		err := q.QueryRow(sqlf(query)+" RETURNING id", args...).Scan(&id)
		return id, err
	}
	res, err := q.Exec(sqlf(query), args...)
	if err != nil {
		return 0, err
	}
	id, err := res.LastInsertId()
	return int(id), err
}

func equalityCI(column string) string {
	if activeSQLDriver == "postgres" {
		return "LOWER(" + column + ") = LOWER(?)"
	}
	return column + " = ? COLLATE NOCASE"
}
