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
	id, err := insertID(a.db, `INSERT INTO messages(chat_id,from_role,text) VALUES(?,?,?)`, chatID, role, text)
	if err != nil {
		return Message{}, err
	}
	message, ok := a.messageByID(id, chatID)
	if !ok {
		return Message{}, errors.New("created message not found")
	}
	return message, nil
}

func (a *App) chats() []Chat {
	rows, err := a.db.Query(sqlf(`SELECT id,order_id,master_id FROM chats ORDER BY created_at DESC,id DESC`))
	if err != nil {
		return nil
	}
	defer rows.Close()

	demoCustomer, _ := a.profile("customer")
	var items []Chat
	for rows.Next() {
		var chatID, orderID, masterID int
		if err := rows.Scan(&chatID, &orderID, &masterID); err != nil {
			continue
		}
		order, ok := a.orderByID(orderID)
		if !ok {
			continue
		}
		master, ok := a.masterByID(masterID)
		if !ok {
			continue
		}
		messages := a.messagesForChat(chatID)
		last := Message{}
		if len(messages) > 0 {
			last = messages[len(messages)-1]
		}
		// Orders created before customer_id existed (or via the legacy
		// unauthenticated path) fall back to the demo customer's name.
		customerName := demoCustomer.Name
		if order.CustomerID > 0 {
			if realCustomer, err := a.profileByID(order.CustomerID); err == nil {
				customerName = realCustomer.Name
			}
		}
		orderCopy := order
		items = append(items, Chat{
			ID:          chatID,
			OrderID:     order.ID,
			OrderTitle:  order.Title,
			Customer:    customerName,
			Master:      master.Name,
			LastMessage: last.Text,
			LastTime:    last.CreatedAt,
			UnreadCount: 0,
			Order:       &orderCopy,
		})
	}
	return items
}

func (a *App) messageByID(id, chatID int) (Message, bool) {
	row := a.db.QueryRow(sqlf(`SELECT id,chat_id,from_role,text,created_at FROM messages WHERE id=? AND chat_id=?`), id, chatID)
	var item Message
	var created string
	if err := row.Scan(&item.ID, &item.ChatID, &item.FromRole, &item.Text, &created); err != nil {
		return Message{}, false
	}
	item.CreatedAt = clock(created)
	return item, true
}

func (a *App) chatByOrderAndMaster(orderID, masterID int) (Chat, bool) {
	for _, chat := range a.chats() {
		if chat.OrderID == orderID && chat.Master == "" {
			continue
		}
		if chat.OrderID == orderID {
			master, ok := a.masterByID(masterID)
			if ok && chat.Master == master.Name {
				return chat, true
			}
		}
	}
	return Chat{}, false
}

func (a *App) ensureChat(orderID, masterID int) (Chat, error) {
	if chat, ok := a.chatByOrderAndMaster(orderID, masterID); ok {
		return chat, nil
	}
	id, err := insertID(a.db, `INSERT INTO chats(order_id,master_id) VALUES(?,?)`, orderID, masterID)
	if err != nil {
		return Chat{}, err
	}
	for _, chat := range a.chats() {
		if chat.ID == id {
			return chat, nil
		}
	}
	return Chat{}, errors.New("created chat not found")
}
