package main

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
)

type ChatsResponse struct {
	Chats []Chat `json:"chats"`
}

type MessagesResponse struct {
	Messages []Message `json:"messages"`
}

type SendMessageRequest struct {
	Text     string `json:"text"`
	FromRole string `json:"fromRole"`
}

type SendMessageResponse struct {
	Message  Message   `json:"message"`
	Messages []Message `json:"messages,omitempty"`
}

func (a *App) chatsHandler(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}
	writeJSON(w, ChatsResponse{Chats: a.chats()})
}

func (a *App) chatDetailHandler(w http.ResponseWriter, r *http.Request) {
	chatID, action, ok := parseChatSubroute(r.URL.Path)
	if !ok {
		writeError(w, http.StatusNotFound, "chat_not_found", "chat not found")
		return
	}
	if action != "messages" {
		writeError(w, http.StatusNotFound, "route_not_found", "route not found")
		return
	}
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, MessagesResponse{Messages: a.messagesForChat(chatID)})
	case http.MethodPost:
		var req SendMessageRequest
		if err := decode(r, &req); err != nil {
			badRequest(w, err)
			return
		}
		message, err := a.createMessage(chatID, req)
		if err != nil {
			badRequest(w, err)
			return
		}
		writeJSON(w, SendMessageResponse{Message: message})
	default:
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	}
}

func (a *App) messages(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, a.messagesForChat(1))
	case http.MethodPost:
		var req SendMessageRequest
		if err := decode(r, &req); err != nil {
			badRequest(w, err)
			return
		}
		message, err := a.createMessage(1, req)
		if err != nil {
			badRequest(w, err)
			return
		}
		if r.URL.Query().Get("wrap") == "1" {
			writeJSON(w, SendMessageResponse{
				Message:  message,
				Messages: a.messagesForChat(1),
			})
			return
		}
		writeJSON(w, a.messagesForChat(1))
	default:
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	}
}

func parseChatSubroute(path string) (int, string, bool) {
	rest := strings.TrimPrefix(path, "/api/chats/")
	parts := strings.Split(strings.Trim(rest, "/"), "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return 0, "", false
	}
	id, err := strconv.Atoi(parts[0])
	if err != nil || id <= 0 {
		return 0, "", false
	}
	return id, parts[1], true
}

func (a *App) createMessage(chatID int, req SendMessageRequest) (Message, error) {
	text := strings.TrimSpace(req.Text)
	if text == "" {
		return Message{}, errors.New("message is empty")
	}
	role := strings.TrimSpace(req.FromRole)
	if role == "" {
		role = "customer"
	}
	if role != "customer" && role != "master" {
		return Message{}, errors.New("fromRole must be customer or master")
	}
	res, err := a.db.Exec(`INSERT INTO messages(chat_id,from_role,text) VALUES(?,?,?)`, chatID, role, text)
	if err != nil {
		return Message{}, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return Message{}, err
	}
	message, ok := a.messageByID(int(id), chatID)
	if !ok {
		return Message{}, errors.New("created message not found")
	}
	return message, nil
}

func (a *App) chats() []Chat {
	messages := a.messagesForChat(1)
	last := Message{}
	if len(messages) > 0 {
		last = messages[len(messages)-1]
	}
	order, _ := a.orderByID(1)
	return []Chat{
		{
			ID:          1,
			OrderID:     order.ID,
			OrderTitle:  order.Title,
			Customer:    "Акрам Осими",
			Master:      "Фаррух Турсунов",
			LastMessage: last.Text,
			LastTime:    last.CreatedAt,
			UnreadCount: 0,
			Order:       &order,
		},
	}
}

func (a *App) messageByID(id, chatID int) (Message, bool) {
	for _, item := range a.messagesForChat(chatID) {
		if item.ID == id {
			return item, true
		}
	}
	return Message{}, false
}
