import { Component } from '@angular/core';

@Component({
  selector: 'app-home',
  templateUrl: 'home.page.html',
  styleUrls: ['home.page.scss'],
})
export class HomePage {
  public f = {
    first: '',
    second: '',
    third: '',
    fourth: '',
  };
  constructor() {}

  send(): any {
    console.log('send');
  }
}
