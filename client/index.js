const { app, BrowserWindow, ipcMain, dialog } = require('electron'); // Добавили ipcMain и dialog
const path = require('path');

function createWindow () {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  win.loadFile('index.html');
  // win.webContents.openDevTools();
}

ipcMain.handle('show-native-dialog', async (event, args) => {
  const win = BrowserWindow.getFocusedWindow();
  
  // Дефолтные настройки для обычного alert
  const options = {
    type: args.type || 'info', // 'info', 'error', 'question'
    title: args.title || 'Уведомление',
    message: args.message || '',
    detail: args.detail || '',
    buttons: args.buttons || ['OK'],
    defaultId: args.defaultId || 0,
    cancelId: args.cancelId || 0
  };

  const result = await dialog.showMessageBox(win, options);
  return result.response; // Возвращает индекс нажатой кнопки
});

ipcMain.handle('show-confirm-delete', async (event, clientName) => {
  const win = BrowserWindow.getFocusedWindow();
  
  const options = {
    type: 'question',
    buttons: ['Отмена', 'Удалить'], // Важно: 'Отмена' — индекс 0, 'Удалить' — индекс 1
    defaultId: 1,
    cancelId: 0,
    title: 'Подтверждение удаления',
    message: `Вы уверены, что хотите удалить клиента?`,
    detail: `Удаление клиента "${clientName}" повлечет за собой очистку всех его тест-драйвов.`
  };

  // Вызываем нативное асинхронное окно
  const result = await dialog.showMessageBox(win, options);
  
  // Возвращаем true, если пользователь нажал кнопку 'Удалить' (индекс 1)
  return result.response === 1;
});

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});