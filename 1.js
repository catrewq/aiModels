///

import React, { useState } from "react";

interface Todo {
  id: number;
  text: string;
  done: boolean;
}

export const TodoApp: React.FC = () => {
  const [input, setInput] = useState("");
  const [todos, setTodos] = useState<Todo[]>([]);

  const addTodo = () => {
    const text = input.trim();
    if (!text) return;
    setTodos((prev) => [
      ...prev,
      { id: Date.now(), text, done: false },
    ]);
    setInput("");
  };

  const toggleTodo = (id: number) => {
    setTodos((prev) =>
      prev.map((t) =>
        t.id === id ? { ...t, done: !t.done } : t
      )
    );
  };

  const removeTodo = (id: number) => {
    setTodos((prev) => prev.filter((t) => t.id !== id));
  };

  return (
    <div style={{ padding: 24, maxWidth: 480 }}>
      <h2>小而美的 Todo 列表</h2>

      <div style={{ display: "flex", gap: 8 }}>
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="输入一件要做的事..."
          style={{ flex: 1, padding: 8 }}
        />
        <button onClick={addTodo}>添加</button>
      </div>

      <ul style={{ marginTop: 16, paddingLeft: 20 }}>
        {todos.length === 0 && <li>还没有任务，先加一个吧～</li>}
        {todos.map((todo) => (
          <li
            key={todo.id}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              marginBottom: 8,
            }}
          >
            <input
              type="checkbox"
              checked={todo.done}
              onChange={() => toggleTodo(todo.id)}
            />
            <span
              style={{
                textDecoration: todo.done ? "line-through" : "none",
                color: todo.done ? "#999" : "#222",
              }}
            >
              {todo.text}
            </span>
            <button onClick={() => removeTodo(todo.id)}>删除</button>
          </li>
        ))}
      </ul>
    </div>
  );
};
