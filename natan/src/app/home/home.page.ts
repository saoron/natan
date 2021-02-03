import { Component } from '@angular/core';
declare let window: any;

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
    window.YuGoFIT.play(
      (res) => {
        alert('got data');
        console.log(res);
      },
      (error) => {
        console.error('error', error);
      }
    );
  }
}
